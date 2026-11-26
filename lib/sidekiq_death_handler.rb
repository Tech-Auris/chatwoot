# Reports jobs that exhausted their retries and landed in the dead set.
#
# Without it nothing watches that set, so a reply that failed every attempt is discovered
# by the customer complaining. For a SendReplyJob the report also names the account, inbox,
# conversation and message, both in the log line and as Sentry tags.
class SidekiqDeathHandler
  def self.call(job, exception)
    new(job, exception).report
  end

  def initialize(job, exception)
    @job = job
    @exception = exception
  end

  # The enrichment is best-effort and the report is not: resolving the message hits the
  # database, and the failures that fill the dead set often come with a database in trouble.
  def report
    tags = safely('context') { context_tags } || {}
    Rails.logger.error(
      "[SIDEKIQ][DEAD] #{job_class} jid=#{@job['jid']} queue=#{@job['queue']} " \
      "error=#{@exception.class}: #{@exception.message}#{tags.map { |key, value| " #{key}=#{value}" }.join}"
    )
    capture(tags)
  rescue StandardError => e
    # A death handler that raises takes the reporting down with the job it was reporting.
    Rails.logger.error "[SIDEKIQ][DEAD] handler failed: #{e.message}"
  end

  private

  def capture(tags)
    ChatwootExceptionTracker.new(@exception, account: safely('account') { message&.account },
                                             tags: tags.merge(job_class: job_class)).capture_exception
  end

  def safely(what)
    yield
  rescue StandardError => e
    Rails.logger.warn "[SIDEKIQ][DEAD] could not resolve #{what}: #{e.class}: #{e.message}"
    nil
  end

  # ActiveJob wraps the real class name; plain Sidekiq workers use 'class'.
  def job_class
    @job['wrapped'] || @job['class']
  end

  # NEVER logged, only used to resolve the message: arguments can carry message content and
  # credentials (WebhookJob sends the webhook secret positionally). The jid is enough to pull
  # the payload from the dead set.
  def job_args
    payload = @job['args']&.first
    payload.is_a?(Hash) ? payload['arguments'] : @job['args']
  end

  def message
    return @message if defined?(@message)

    @message = job_class.to_s == 'SendReplyJob' ? Message.find_by(id: job_args&.first) : nil
  end

  def context_tags
    return {} if message.blank?

    { account_id: message.account_id, inbox_id: message.inbox_id,
      conversation_id: message.conversation_id, message_id: message.id }
  end
end
