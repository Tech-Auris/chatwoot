# How many messages failed with each error, most frequent first. The error
# sits in `content_attributes`, whose legacy rows are double-encoded JSON —
# `#>>'{}'` unwraps both shapes (same as Conversation#last_ctwa_referral_at).
module Messages::FailureReasons
  ERROR_SQL = Arel.sql("((messages.content_attributes#>>'{}')::jsonb ->> 'external_error')")

  module_function

  def call(messages)
    messages.reorder(nil).where(status: :failed).group(ERROR_SQL).count
            .map { |error, count| { error: error, count: count } }
            .sort_by { |reason| -reason[:count] }
  end
end
