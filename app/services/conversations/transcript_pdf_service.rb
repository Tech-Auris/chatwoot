# Renders a conversation transcript as a downloadable PDF.
#
# ## Concurrency
#
# Grover spawns its own Node + Chromium subprocess per call, so every
# generation is fully isolated at the OS level. A user downloading transcript
# for conversation X at the same instant as another user downloading the same
# X cannot contaminate each other's PDF — each render owns its own Chromium
# heap.
#
# The remaining risk is resource exhaustion: each Chromium takes ~150MB of
# RAM, so a burst of concurrent requests could OOM the container. To prevent
# that we gate every render behind a process-wide semaphore. Callers that
# can't acquire a slot within the wait timeout get a `OverloadError`, which
# the controller turns into `429 Too Many Requests`.
#
# The semaphore is per Rails process (not per container / not per account) —
# it caps how many Chromium instances live at any given moment on this Puma
# worker, not across the whole cluster.
class Conversations::TranscriptPdfService
  class OverloadError < StandardError; end

  # Max Chromium processes running simultaneously per Rails worker. 2 is a
  # conservative default that keeps peak memory under ~300MB for this feature.
  # Bump via ENV when the container has more headroom.
  MAX_CONCURRENT = ENV.fetch('TRANSCRIPT_PDF_MAX_CONCURRENT', 2).to_i

  # How long a request will wait to grab a semaphore slot before giving up
  # and asking the client to retry. Chosen so a warm request (~1-2s) never
  # trips this, but a fully saturated worker returns fast enough that the
  # frontend can show "try again in a few seconds".
  ACQUIRE_TIMEOUT = ENV.fetch('TRANSCRIPT_PDF_ACQUIRE_TIMEOUT_SEC', 15).to_i

  SEMAPHORE = Concurrent::Semaphore.new(MAX_CONCURRENT)

  def initialize(conversation:)
    @conversation = conversation
  end

  def perform
    acquired = SEMAPHORE.try_acquire(1, ACQUIRE_TIMEOUT)
    raise OverloadError, 'Too many transcript PDF renders in flight' unless acquired

    begin
      Grover.new(sanitize_for_grover(render_html), display_url: display_url).to_pdf
    ensure
      SEMAPHORE.release
    end
  end

  # Public so the controller can build a matching Content-Disposition.
  def filename
    "transcricao_#{@conversation.display_id}.pdf"
  end

  private

  # Grover embeds the HTML into JavaScript source before running it in
  # Chromium, so any char JS treats as a line terminator inside a string
  # literal breaks the payload with "Unterminated string in JSON". The two
  # culprits are U+2028 (LINE SEPARATOR) and U+2029 (PARAGRAPH SEPARATOR) —
  # both valid Unicode, both smuggled in by anything that pastes copy from
  # Word / macOS / e-mail signatures (a real production case had them in an
  # agent name). Rewrite them as HTML numeric entities so the rendered PDF
  # still shows a paragraph break and the JS bridge no longer chokes.
  JS_BREAKING_CHARS = { "\u2028" => '&#x2028;', "\u2029" => '&#x2029;' }.freeze

  def sanitize_for_grover(html)
    html.gsub(/[  ]/, JS_BREAKING_CHARS)
  end

  def render_html
    ApplicationController.renderer.new(
      http_host: display_host,
      https: display_protocol == 'https'
    ).render(
      template: 'api/v1/accounts/conversations/transcript_pdf',
      layout: false,
      assigns: {
        conversation: @conversation,
        account: @conversation.account,
        contact: @conversation.contact,
        agent: @conversation.assignee,
        inbox: @conversation.inbox,
        messages: @conversation.messages.chat.select(&:conversation_transcriptable?)
      }
    )
  end

  # Grover uses display_url to resolve relative URLs (attachments served from
  # ActiveStorage proxy paths). Point it at whatever the frontend uses so
  # links inside the PDF stay clickable.
  def display_url
    "#{display_protocol}://#{display_host}/"
  end

  def display_host
    URI.parse(frontend_url).host
  rescue URI::InvalidURIError
    'localhost'
  end

  def display_protocol
    URI.parse(frontend_url).scheme.presence || 'https'
  rescue URI::InvalidURIError
    'https'
  end

  def frontend_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end
end
