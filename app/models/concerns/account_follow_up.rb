# Follow-up (FUP) setup of the account, read by the n8n FUP workflow through
# the account API (`settings.follow_up`) and the webhook payloads:
#
#   steps     minutes to wait before each FUP, counted from the previous one
#   end_flow  what happens once every FUP went unanswered: after
#             `wait_minutes` the conversation goes to Perdido and is handed to
#             the team with `summary_message` (`@resumo@` is replaced by the AI
#             summary) and `escalation_message` is sent to the patient
module AccountFollowUp
  extend ActiveSupport::Concern

  MAX_FOLLOW_UP_STEPS = 5

  included do
    validate :validate_follow_up, if: -> { follow_up.present? }
  end

  def follow_up
    settings&.dig('follow_up')
  end

  def follow_up=(value)
    self.settings = (settings || {}).merge('follow_up' => value&.deep_stringify_keys)
  end

  private

  def validate_follow_up
    steps = follow_up['steps']
    valid_steps = steps.is_a?(Array) && steps.size <= MAX_FOLLOW_UP_STEPS && steps.all? { |step| positive_integer?(step) }
    errors.add(:follow_up, I18n.t('errors.account.follow_up.invalid_steps', max: MAX_FOLLOW_UP_STEPS)) unless valid_steps

    wait_minutes = follow_up.dig('end_flow', 'wait_minutes')
    errors.add(:follow_up, I18n.t('errors.account.follow_up.invalid_wait_minutes')) unless wait_minutes.nil? || positive_integer?(wait_minutes)
  end

  def positive_integer?(value)
    value.is_a?(Integer) && value.positive?
  end
end
