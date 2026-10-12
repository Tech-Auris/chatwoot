# Follow-up (FUP) setup of the account, read by the n8n FUP workflow through
# the account API (`settings.follow_up`) and the webhook payloads:
#
#   steps     minutes to wait before each FUP, counted from the previous one
#   end_flow  what happens after the last FUP: once `wait_minutes` pass
#             without an answer the conversation goes to Perdido; when
#             `enabled` ("Escalar para o time") it is also handed to the team
#             with `summary_message` (`@resumo@` is replaced by the AI
#             summary) and `escalation_message` is sent to the patient.
#             A blank `wait_minutes` takes the installation default
#             (Settings → General → Follow-up).
module AccountFollowUp
  extend ActiveSupport::Concern

  MAX_FOLLOW_UP_STEPS = 5
  END_WAIT_CONFIG = 'FOLLOW_UP_END_WAIT_MINUTES'.freeze
  DEFAULT_END_WAIT_MINUTES = 60

  included do
    validate :validate_follow_up, if: -> { follow_up.present? }
  end

  def follow_up
    settings&.dig('follow_up')
  end

  def follow_up=(value)
    self.settings = (settings || {}).merge('follow_up' => value&.deep_stringify_keys)
  end

  # What n8n reads (webhook payloads): the setup with the end wait always
  # filled, from the account or the installation default. `steps` stays out
  # while the account has none, so the secretary keeps its own fallback.
  def follow_up_payload
    end_flow = (follow_up&.dig('end_flow') || {}).merge('wait_minutes' => follow_up_end_wait_minutes)
    (follow_up || {}).merge('end_flow' => end_flow)
  end

  def follow_up_end_wait_minutes
    follow_up&.dig('end_flow', 'wait_minutes').presence || self.class.default_follow_up_end_wait_minutes
  end

  class_methods do
    def default_follow_up_end_wait_minutes
      minutes = GlobalConfigService.load(END_WAIT_CONFIG, DEFAULT_END_WAIT_MINUTES).to_i
      minutes.positive? ? minutes : DEFAULT_END_WAIT_MINUTES
    end
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
