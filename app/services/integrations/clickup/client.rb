# Thin HTTP wrapper around the ClickUp REST API. Only the endpoints the
# Feedback tickets flow touches are exposed here; all callers go through
# this class (never HTTParty directly) so retry, timeout, and error
# translation stay uniform.
#
# Error hierarchy is intentionally shallow — every job that talks to
# ClickUp only needs to distinguish "auth is wrong, give up" from
# "transient failure, retry" so we only expose those two flavors.
class Integrations::Clickup::Client
  BASE_URL = 'https://api.clickup.com/api/v2'.freeze
  DEFAULT_TIMEOUT = 15

  class Error < StandardError; end
  class Unauthorized < Error; end
  class ProviderUnavailable < Error; end

  def initialize(api_key: nil)
    @api_key = api_key.presence || GlobalConfig.get('CLICKUP_API_KEY')['CLICKUP_API_KEY']
  end

  def configured?
    @api_key.present?
  end

  def create_task(list_id:, name:, description: '', custom_fields: [])
    post_json(
      "/list/#{list_id}/task",
      { name: name, description: description.to_s, custom_fields: custom_fields }
    )
  end

  # Tasks of a list, one page at a time. `include_closed: false` already drops
  # the won/lost ones, which is exactly the slice the sales autocomplete wants —
  # the lost column alone holds thousands of tasks nobody searches for.
  def list_tasks(list_id:, page: 0, include_closed: false)
    get_json("/list/#{list_id}/task", page: page, include_closed: include_closed, subtasks: false)
  end

  # ClickUp takes dates as epoch milliseconds.
  def update_task(task_id, attributes)
    put_json("/task/#{task_id}", attributes)
  end

  # Tags are addressed by name, and the endpoint is idempotent — adding one the
  # task already carries is a no-op rather than an error.
  def add_tag(task_id, tag_name)
    post_json("/task/#{task_id}/tag/#{ERB::Util.url_encode(tag_name)}", {})
  end

  def add_comment(task_id, text)
    post_json("/task/#{task_id}/comment", { comment_text: text.to_s })
  end

  # Uploads a file to a task. `io` is an IO-like object (typically the
  # Tempfile ActiveStorage::Blob#open yields). HTTParty pulls the multipart
  # filename from `file.path` basename, so an ActiveStorage tempfile
  # (`RackMultipart-abc123` with no extension) reaches ClickUp as an
  # extensionless upload and gets rejected with `400 Invalid upload`.
  # Copy the bytes into a scratch directory under the original filename so
  # HTTParty stamps the multipart part with the real name.
  def upload_attachment(task_id, io:, filename:)
    Dir.mktmpdir('clickup-attachment') do |dir|
      path = File.join(dir, File.basename(filename.to_s))
      File.open(path, 'wb') { |f| IO.copy_stream(io, f) }

      File.open(path, 'rb') do |file|
        response = HTTParty.post(
          "#{BASE_URL}/task/#{task_id}/attachment",
          headers: { 'Authorization' => auth_header },
          multipart: true,
          body: { attachment: file },
          timeout: DEFAULT_TIMEOUT
        )
        return parse(response)
      end
    end
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise ProviderUnavailable, e.message
  end

  def create_webhook(team_id:, endpoint:, events:)
    post_json("/team/#{team_id}/webhook", { endpoint: endpoint, events: events })
  end

  def delete_webhook(webhook_id)
    response = HTTParty.delete(
      "#{BASE_URL}/webhook/#{webhook_id}",
      headers: default_headers,
      timeout: DEFAULT_TIMEOUT
    )
    parse(response)
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise ProviderUnavailable, e.message
  end

  private

  def get_json(path, query = {})
    response = HTTParty.get(
      "#{BASE_URL}#{path}",
      headers: default_headers,
      query: query,
      timeout: DEFAULT_TIMEOUT
    )
    parse(response)
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise ProviderUnavailable, e.message
  end

  def put_json(path, body)
    response = HTTParty.put(
      "#{BASE_URL}#{path}",
      headers: default_headers,
      body: body.to_json,
      timeout: DEFAULT_TIMEOUT
    )
    parse(response)
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise ProviderUnavailable, e.message
  end

  def post_json(path, body)
    response = HTTParty.post(
      "#{BASE_URL}#{path}",
      headers: default_headers,
      body: body.to_json,
      timeout: DEFAULT_TIMEOUT
    )
    parse(response)
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise ProviderUnavailable, e.message
  end

  def default_headers
    {
      'Authorization' => auth_header,
      'Content-Type' => 'application/json'
    }
  end

  def auth_header
    @api_key.to_s
  end

  def parse(response)
    raise Unauthorized, 'ClickUp API rejected the credentials' if response.code == 401

    unless response.success?
      # ClickUp returns { "err": "...", "ECODE": "..." } on failures.
      err = response.parsed_response.is_a?(Hash) ? response.parsed_response['err'] : response.body
      raise ProviderUnavailable, "ClickUp #{response.code}: #{err}"
    end

    response.parsed_response
  end
end
