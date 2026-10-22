# A contact that asked not to get marketing: campaigns and follow-ups skip it,
# while replies, reminders and the patient's own flows keep going out. Anything
# can turn it on (an agent, Meta's #131050, the template's opt-out button, the
# AI); only a human turns it off — the API enforces that, not this model.
module MarketingOptOutable
  extend ActiveSupport::Concern

  SOURCES = %w[manual meta template_button ai].freeze

  included do
    validates :marketing_opt_out_source, inclusion: { in: SOURCES }, allow_nil: true
  end

  def opt_out!(source:, user: nil)
    return if marketing_opt_out?

    update!(marketing_opt_out: true, marketing_opt_out_at: Time.current, marketing_opt_out_source: source)
    note_opt_out_change(I18n.t("conversations.activity.marketing_opt_out.#{source}", user_name: user&.name))
  end

  def clear_opt_out!(user:)
    return unless marketing_opt_out?

    update!(marketing_opt_out: false, marketing_opt_out_at: nil, marketing_opt_out_source: nil)
    note_opt_out_change(I18n.t('conversations.activity.marketing_opt_out.cleared', user_name: user.name))
  end

  private

  # Noted on the contact's conversations still in progress, where the team works.
  def note_opt_out_change(content)
    conversations.where.not(status: :resolved).find_each do |conversation|
      Conversations::ActivityMessageJob.perform_later(
        conversation, { account_id: account_id, inbox_id: conversation.inbox_id, message_type: :activity, content: content }
      )
    end
  end
end
