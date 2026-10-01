# == Schema Information
#
# Table name: webhooks
#
#  id            :bigint           not null, primary key
#  name          :string
#  secret        :string
#  subscriptions :jsonb
#  url           :text
#  webhook_type  :integer          default("account_type")
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :integer
#  inbox_id      :integer
#
# Indexes
#
#  index_webhooks_on_account_id_and_url  (account_id,url) UNIQUE
#

class Webhook < ApplicationRecord
  belongs_to :account
  belongs_to :inbox, optional: true

  include WebhookSecretable

  validates :account_id, presence: true
  validates :url, uniqueness: { scope: [:account_id] }, format: URI::DEFAULT_PARSER.make_regexp(%w[http https])
  validate :validate_webhook_subscriptions
  validate :url_not_a_secretary_version
  enum webhook_type: { account_type: 0, inbox_type: 1 }

  ALLOWED_WEBHOOK_EVENTS = %w[conversation_status_changed conversation_updated conversation_created contact_created contact_updated
                              message_created message_incoming message_outgoing message_updated webwidget_triggered
                              inbox_created inbox_updated conversation_typing_on conversation_typing_off conversation_recording
                              provider_event_received internal_chat_message_created internal_chat_message_updated
                              internal_chat_message_deleted internal_chat_channel_updated funnel_updated].freeze

  private

  # The secretary already receives every message through its Super Admin
  # setup; a webhook to the same URL would make it answer twice.
  def url_not_a_secretary_version
    errors.add(:url, I18n.t('errors.webhook.secretary_url')) if SecretaryVersion.exists?(webhook_url: url.to_s.strip)
  end

  def validate_webhook_subscriptions
    invalid_subscriptions = !subscriptions.instance_of?(Array) ||
                            subscriptions.blank? ||
                            (subscriptions.uniq - ALLOWED_WEBHOOK_EVENTS).length.positive?
    errors.add(:subscriptions, I18n.t('errors.webhook.invalid')) if invalid_subscriptions
  end
end

Webhook.include_mod_with('Audit::Webhook')
