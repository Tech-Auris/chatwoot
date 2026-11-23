# The agenda of a clinic that schedules in Google Calendar (`erp_sources` id 1),
# read with the Google account the clinics share their calendars with (see
# Agenda::GoogleConnection).
#
# Which calendars, from the account's integration config:
#
# - `calendars`: a list of `{ "calendar_id": ..., "professional": "Dra. Ana" }`,
#   for a clinic with one calendar per professional: the professional is the
#   calendar.
# - otherwise `calendar_id`: a single calendar, where the professional is the
#   `profissional:` line our Criar Evento writes in the description. Events
#   created elsewhere, without that line, have no professional.
#
# Events created by the AI are titled `patient | appointment | phone`; the
# Confirmar Evento flow puts ✅ in front of the confirmed ones. All-day events
# (holidays, days off) aren't appointments and are left out.
class Agenda::Sources::GoogleCalendar < Agenda::Source
  API = 'https://www.googleapis.com/calendar/v3'.freeze
  TIME_ZONE = 'America/Sao_Paulo'.freeze
  CONFIRMED = /\A\s*✅️?\s*/
  EVENT_KEYS = %w[id summary description start end].freeze
  EVENTS_TTL = 2.minutes
  HTTP_TIMEOUT = 15

  def professionals
    return calendars.map { |calendar| { id: calendar[:id], name: calendar[:professional] || calendar[:id] } } if per_professional?

    (@appointments || []).filter_map { |appointment| appointment[:professional_id] }.uniq.map { |name| { id: name, name: name } }
  end

  def appointments(from, to)
    @appointments = calendars.flat_map do |calendar|
      events(calendar[:id], from, to).filter_map { |event| appointment(event, calendar) }
    end
  end

  private

  def appointment(event, calendar)
    return if event.dig('start', 'dateTime').blank?

    title = event['summary'].to_s
    parts = title.sub(CONFIRMED, '').split('|').map(&:strip)
    details = details_of(event['description'])
    professional_id, professional_name = professional_of(calendar, details)
    {
      id: event['id'], starts_at: event.dig('start', 'dateTime'), ends_at: event.dig('end', 'dateTime'),
      patient_name: parts.first.presence, professional_id: professional_id, professional_name: professional_name,
      procedure_name: details['procedimento'].presence || (parts[1] if parts.size > 2),
      status: title.match?(CONFIRMED) ? 'confirmed' : 'scheduled'
    }
  end

  # [id, name]: the calendar's professional, or the description's `profissional:`.
  def professional_of(calendar, details)
    return [calendar[:id], calendar[:professional] || calendar[:id]] if per_professional?

    name = details['profissional'].presence
    [name, name]
  end

  # The `key: value` lines of the description (HTML once edited in Google's UI).
  def details_of(description)
    text = CGI.unescapeHTML(description.to_s.gsub(%r{<br\s*/?>|</p>|</div>}i, "\n").gsub(/<[^>]+>/, ''))
    text.lines.each_with_object({}) do |line, details|
      key, value = line.split(':', 2)
      details[key.strip.downcase] ||= value.squish if value
    end
  end

  def calendars
    @calendars ||= per_professional? ? professional_calendars : [{ id: integration.config['calendar_id'].to_s.strip }]
    raise Agenda::Source::Error, I18n.t('agenda.errors.calendar_missing') if @calendars.first[:id].empty?

    @calendars
  end

  def per_professional?
    professional_calendars.any?
  end

  def professional_calendars
    @professional_calendars ||= Array(integration.config['calendars']).filter_map do |calendar|
      calendar = calendar.to_h
      id = calendar['calendar_id'].to_s.strip
      { id: id, professional: calendar['professional'].to_s.strip.presence } if id.present?
    end
  end

  def events(calendar_id, from, to)
    cached('events', calendar_id, from.iso8601, to.iso8601, expires_in: EVENTS_TTL) do
      zone = Time.find_zone(TIME_ZONE)
      query = { timeMin: zone.local(from.year, from.month, from.day).iso8601, timeMax: zone.local(to.year, to.month, to.day).tomorrow.iso8601,
                singleEvents: true, orderBy: 'startTime', maxResults: 2500, timeZone: TIME_ZONE }
      pages(calendar_id, query)
    end
  end

  def pages(calendar_id, query)
    events = []
    loop do
      body = get(calendar_id, query)
      events.concat(body['items'].to_a.map { |event| event.slice(*EVENT_KEYS) })
      break if body['nextPageToken'].blank?

      query = query.merge(pageToken: body['nextPageToken'])
    end
    events
  end

  def get(calendar_id, query)
    headers = { 'Authorization' => "Bearer #{Agenda::GoogleConnection.access_token}" }
    response = HTTParty.get("#{API}/calendars/#{ERB::Util.url_encode(calendar_id)}/events", query: query, headers: headers, timeout: HTTP_TIMEOUT)
    if [403, 404].include?(response.code)
      raise Agenda::Source::Error, I18n.t('agenda.errors.calendar_not_shared', calendar: calendar_id, email: Agenda::GoogleConnection.email)
    end
    raise Agenda::Source::Error, I18n.t('agenda.errors.google_status', status: response.code) unless response.success?

    response.parsed_response
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError
    raise Agenda::Source::Error, I18n.t('agenda.errors.unreachable')
  end
end
