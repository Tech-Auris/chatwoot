# Autocomplete of prospects for the sales screen, reading the ClickUp pipeline.
#
# The open pipeline is fetched whole and filtered here rather than queried per
# keystroke: ClickUp cannot search across a name, an e-mail custom field and a
# phone custom field in one call. Won and lost are open columns in ClickUp, so
# the walk asks only for the other statuses — the lost column alone holds
# thousands of tasks and used to push live deals past the page limit.
class Sales::ClickupProspectSearchService
  # ClickUp pages at 100; the open pipeline fits in a handful of pages. The cap
  # only guards against a runaway walk.
  MAX_PAGES = 20
  CACHE_TTL = 5.minutes
  MAX_RESULTS = 20

  # Custom field ids of the Pipeline list. They are stable per list, and reading
  # by id is what keeps this working when somebody renames a field.
  EMAIL_FIELD_ID = 'b1b10c7f-c17a-417c-b746-f8036956d44e'.freeze
  PHONE_FIELD_ID = '4e7406d4-8122-4547-a24d-d9d060920d58'.freeze
  CLINIC_FIELD_ID = '07e5b8ee-e9ab-416b-92a4-bff90aacce9c'.freeze
  # Reservation deadline lives in this dedicated ClickUp custom field
  # ("Vencimento da Reserva") — kept apart from the task's native
  # due_date so the story deadline and the reservation deadline can
  # move independently.
  RESERVATION_DUE_FIELD_ID = '709b1aad-9f10-4e5c-bfb5-3601b6200e91'.freeze
  # Meta ad click id the lead form records; feeds the Purchase sent on payment.
  FBCLID_FIELD_ID = '4b672263-1aa6-4f81-ba21-0220a84814fe'.freeze
  # The sales team, ClickUp instance and public proposal all speak São
  # Paulo local time — the reservation deadline is anchored to that day
  # regardless of where the Rails server is.
  SALES_TIMEZONE = 'America/Sao_Paulo'.freeze

  # A deal that was won or lost is not somebody to build a plan for.
  CLOSED_DEAL_STATUSES = %w[ganho perdido].freeze

  class NotConfigured < StandardError; end

  def initialize(client: nil, list_id: nil)
    @client = client
    @list_id = list_id
  end

  def search(term)
    normalized = normalize(term)
    return [] if normalized.blank?

    prospects.select { |prospect| matches?(prospect, normalized) }.first(MAX_RESULTS)
  end

  # Not filtered by status: the reservations report mirrors what happened to a
  # deal, and being won or lost is exactly what it has to see. Those are not in
  # the cached walk, so they are read one by one.
  def find(task_id)
    prospects.find { |prospect| prospect[:task_id] == task_id } || find_task(task_id)
  end

  private

  def client
    @client ||= Integrations::Clickup::Client.new
  end

  def list_id
    @list_id ||= GlobalConfig.get('CLICKUP_PIPELINE_LIST_ID')['CLICKUP_PIPELINE_LIST_ID'].presence
    raise NotConfigured, 'Configure a lista do pipeline do ClickUp em Settings → ClickUp' if @list_id.blank?

    @list_id
  end

  # Cached for the whole screen rather than per keystroke: without it, typing a
  # name would fan out a page-walk of the pipeline for every letter.
  def prospects
    @prospects ||= Rails.cache.fetch("sales/clickup_prospects/#{list_id}", expires_in: CACHE_TTL) do
      fetch_all_tasks.map { |task| serialize(task) }
    end
  end

  def fetch_all_tasks
    statuses = open_deal_statuses
    tasks = []
    MAX_PAGES.times do |page|
      response = client.list_tasks(list_id: list_id, page: page, statuses: statuses)
      batch = response['tasks'] || []
      tasks.concat(batch)
      return tasks if response['last_page'] || batch.empty?
    end

    Rails.logger.warn("[sales] ClickUp pipeline #{list_id} has more than #{MAX_PAGES} pages of open deals; the rest is not searchable")
    tasks
  end

  def open_deal_statuses
    client.get_list(list_id)['statuses']
          .pluck('status')
          .reject { |status| CLOSED_DEAL_STATUSES.include?(normalize(status)) }
  end

  def find_task(task_id)
    task = Rails.cache.fetch("sales/clickup_prospect/#{task_id}", expires_in: CACHE_TTL) { client.get_task(task_id) }
    serialize(task) if task.dig('list', 'id') == list_id
  end

  def serialize(task)
    {
      task_id: task['id'],
      name: task['name'],
      clinic_name: custom_field(task, CLINIC_FIELD_ID),
      email: custom_field(task, EMAIL_FIELD_ID),
      phone: custom_field(task, PHONE_FIELD_ID),
      status: task.dig('status', 'status'),
      status_color: task.dig('status', 'color'),
      # Reservation deadline mirrored from the "Vencimento da Reserva"
      # ClickUp custom field. The task's native `due_date` used to feed
      # this — moved so operators can edit the story deadline in ClickUp
      # without moving the reservation with it.
      due_date: custom_field(task, RESERVATION_DUE_FIELD_ID)&.to_i,
      url: task['url'],
      fbclid: custom_field(task, FBCLID_FIELD_ID),
      created_at: task['date_created']&.to_i
    }
  end

  def custom_field(task, field_id)
    field = (task['custom_fields'] || []).find { |candidate| candidate['id'] == field_id }
    field&.dig('value').presence
  end

  # Every word typed has to show up somewhere, in any order, so "farly gold"
  # finds "Farly Goldincision Leads". Spaces are also ignored as a whole, since
  # a brand typed as "gold incision" is stored as "Goldincision".
  def matches?(prospect, term)
    haystack = [prospect[:name], prospect[:clinic_name], prospect[:email], normalize_digits(prospect[:phone])]
               .compact.map { |value| normalize(value) }.join(' ')

    term.split.all? { |word| haystack.include?(word) } || haystack.delete(' ').include?(term.delete(' '))
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip
  end

  # A phone typed as "981402211" has to find "+55 61 98140-2211".
  def normalize_digits(value)
    value.to_s.gsub(/\D/, '')
  end
end
