# A contact the AI secretary never answers (a doctor of the clinic, a partner):
# every new message of theirs, in any inbox or conversation, arrives with the
# AI off (Conversations::AiAutoOffService). Turning it off also turns the AI
# off in the conversations in progress; turning it back on only applies to
# the next messages, so the AI never returns in the middle of a human reply.
module AiDisableable
  extend ActiveSupport::Concern

  included do
    belongs_to :ai_disabled_by, class_name: 'User', optional: true
  end

  def disable_ai!(user)
    return if ai_disabled?

    update!(ai_disabled: true, ai_disabled_at: Time.current, ai_disabled_by: user)
    Current.ai_off_reason = :contact_manual
    conversations_in_progress.find_each { |conversation| conversation.set_ai_status!(false) }
  ensure
    Current.ai_off_reason = nil
  end

  def enable_ai!(user)
    return unless ai_disabled?

    update!(ai_disabled: false, ai_disabled_at: nil, ai_disabled_by: nil)
    content = I18n.t('conversations.activity.ai_auto_off.contact_enabled', user_name: user.name, locale: account.locale)
    conversations_in_progress.find_each do |conversation|
      Conversations::ActivityMessageJob.perform_later(
        conversation, { account_id: account_id, inbox_id: conversation.inbox_id, message_type: :activity, content: content }
      )
    end
  end

  private

  def conversations_in_progress
    conversations.where.not(status: :resolved)
  end
end
