# Autocomplete of prospects for the sales screen, reading the ClickUp pipeline.
#
# The list is fetched whole and filtered here rather than queried per keystroke:
# ClickUp cannot search across a name, an e-mail custom field and a phone custom
# field in one call, and the open pipeline is a few hundred tasks — the lost
# column, which holds thousands, is excluded by the API itself.
class Sales::ClickupProspectSearchService
  # ClickUp pages at 100; the open pipeline fits in a handful of pages.
  MAX_PAGES = 10
  CACHE_TTL = 5.minutes
  MAX_RESULTS = 20

  # Custom field ids of the Pipeline list. They are stable per list, and reading
  # by id is what keeps this working when somebody renames a field.
  EMAIL_FIELD_ID = 'b1b10c7f-c17a-417c-b746-f8036956d44e'.freeze
  PHONE_FIELD_ID = '4e7406d4-8122-4547-a24d-d9d060920d58'.freeze
  CLINIC_FIELD_ID = '07e5b8ee-e9ab-416b-92a4-bff90aacce9c'.freeze

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

  def find(task_id)
    prospects.find { |prospect| prospect[:task_id] == task_id }
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
    (0...MAX_PAGES).each_with_object([]) do |page, tasks|
      response = client.list_tasks(list_id: list_id, page: page)
      batch = response['tasks'] || []
      tasks.concat(batch)
      break tasks if response['last_page'] || batch.empty?
    end
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
      # ClickUp owns the deadline; the reservation report mirrors it from here.
      due_date: task['due_date'].presence&.to_i,
      url: task['url']
    }
  end

  def custom_field(task, field_id)
    field = (task['custom_fields'] || []).find { |candidate| candidate['id'] == field_id }
    field&.dig('value').presence
  end

  # The operator types a name, an e-mail or a phone — one or the other, never a
  # combination — so every field is matched against the same term.
  def matches?(prospect, term)
    [prospect[:name], prospect[:clinic_name], prospect[:email], normalize_digits(prospect[:phone])]
      .compact
      .any? { |value| normalize(value).include?(term) }
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.strip
  end

  # A phone typed as "981402211" has to find "+55 61 98140-2211".
  def normalize_digits(value)
    value.to_s.gsub(/\D/, '')
  end
end
