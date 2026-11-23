# The agenda of ERP 2 (`erp_sources` id 2), read from its REST API with the
# account's `access_token` (header `x-access-token`). The base URL is the ERP's
# `api_url`, filled in on the ERP in Super Admin.
#
# - professionals: `professional/list?ativo=1`
# - appointments: `appoints/search` for the period, every professional at once.
#   Each brings only the patient id, so names come from `patient/search`, one
#   call per patient: cached for 12 hours and looked up in parallel within a
#   time budget; whatever is left is filled by the screen's next request.
# - procedure names: `procedures/list`, optional (the agenda shows without them).
class Agenda::Sources::Erp2 < Agenda::Source
  class NotFound < Agenda::Source::Error; end

  STATUS_MAP = {
    1 => 'scheduled', 7 => 'confirmed', 15 => 'rescheduled',
    4 => 'waiting', 101 => 'waiting',
    2 => 'in_progress', 5 => 'in_progress', 103 => 'in_progress', 105 => 'in_progress',
    3 => 'attended', 6 => 'no_show',
    11 => 'canceled', 16 => 'canceled', 22 => 'canceled'
  }.freeze
  APPOINTMENT_KEYS = %w[agendamento_id data horario duracao paciente_id profissional_id procedimento_id status_id].freeze
  TIME_ZONE = 'America/Sao_Paulo'.freeze
  HTTP_TIMEOUT = 15
  NAME_THREADS = 8
  NAME_BUDGET = 6.seconds
  LIST_TTL = 1.hour
  APPOINTMENTS_TTL = 2.minutes
  NAME_TTL = 12.hours

  def professionals
    @professionals ||= cached('professionals', expires_in: LIST_TTL) do
      get('professional/list', ativo: 1).map do |professional|
        id = professional['profissional_id'].to_s
        { id: id, name: professional['nome'].presence || id }
      end
    end
  end

  def appointments(from, to)
    rows = cached('appointments', from.iso8601, to.iso8601, expires_in: APPOINTMENTS_TTL) do
      get('appoints/search', data_start: from.strftime('%d-%m-%Y'), data_end: to.strftime('%d-%m-%Y')).map { |row| row.slice(*APPOINTMENT_KEYS) }
    end
    names = patient_names(rows.filter_map { |row| row['paciente_id']&.to_s }.uniq)
    rows.map { |row| appointment(row, names) }
  end

  def complete?
    @complete != false
  end

  private

  def appointment(row, names)
    starts_at = starts_at_of(row)
    professional_id = row['profissional_id'].to_s
    {
      id: row['agendamento_id'].to_s,
      starts_at: starts_at.iso8601,
      ends_at: ends_at_of(starts_at, row)&.iso8601,
      patient_name: names[row['paciente_id'].to_s].presence,
      professional_id: professional_id,
      professional_name: professional_names[professional_id],
      procedure_name: procedure_names[row['procedimento_id'].to_s],
      status: STATUS_MAP.fetch(row['status_id'].to_i, 'scheduled')
    }
  end

  # `duracao` is in minutes; zero when the ERP doesn't say.
  def ends_at_of(starts_at, row)
    starts_at + row['duracao'].to_i.minutes if row['duracao'].to_i.positive?
  end

  # `data` comes as dd-mm-yyyy and `horario` as HH:MM:SS, in the clinic's time.
  def starts_at_of(row)
    Time.find_zone(TIME_ZONE).parse("#{Date.strptime(row['data'], '%d-%m-%Y').iso8601} #{row['horario']}")
  end

  def professional_names
    @professional_names ||= professionals.to_h { |professional| [professional[:id], professional[:name]] }
  end

  def procedure_names
    @procedure_names ||= cached('procedures', expires_in: LIST_TTL) do
      get('procedures/list').to_h { |procedure| [procedure['procedimento_id'].to_s, procedure['nome']] }
    end
  rescue Agenda::Source::Error
    @procedure_names = {}
  end

  # Names already cached, plus as many of the missing ones as the time budget
  # allows. A patient the ERP doesn't find is cached as blank.
  def patient_names(ids)
    names = ids.index_with { |id| Rails.cache.read(name_key(id)) }
    deadline = NAME_BUDGET.from_now
    names.select { |_id, name| name.nil? }.keys.each_slice(NAME_THREADS) do |slice|
      break if Time.current > deadline

      names.merge!(lookup_names(slice))
    end
    @complete = names.values.none?(&:nil?)
    names
  end

  def lookup_names(ids)
    found = ids.map { |id| Thread.new { [id, fetch_patient_name(id)] } }.map(&:value).to_h.compact
    found.each { |id, name| Rails.cache.write(name_key(id), name, expires_in: NAME_TTL) }
  end

  def fetch_patient_name(id)
    get('patient/search', paciente_id: id)['nome'].to_s
  rescue NotFound
    ''
  rescue Agenda::Source::Error
    nil
  end

  def name_key(id)
    ['agenda', integration.id, 'patient', id]
  end

  def get(path, query = {})
    response = HTTParty.get("#{base_url}/#{path}", query: query, headers: { 'x-access-token' => integration.config['access_token'].to_s },
                                                   timeout: HTTP_TIMEOUT)
    check!(response)
    response.parsed_response['content']
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError
    raise Agenda::Source::Error, I18n.t('agenda.errors.unreachable')
  end

  def check!(response)
    raise NotFound if response.code == 409
    raise Agenda::Source::Error, I18n.t('agenda.errors.unauthorized') if [401, 403].include?(response.code)

    body = response.parsed_response
    return if response.success? && body.is_a?(Hash) && body['success']

    raise Agenda::Source::Error, I18n.t('agenda.errors.erp_status', status: response.code)
  end

  def base_url
    url = integration.erp_source.api_url.presence
    raise Agenda::Source::Error, I18n.t('agenda.errors.api_url_missing') unless url

    url.chomp('/')
  end
end
