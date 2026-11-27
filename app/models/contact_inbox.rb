# == Schema Information
#
# Table name: contact_inboxes
#
#  id            :bigint           not null, primary key
#  hmac_verified :boolean          default(FALSE)
#  pubsub_token  :string
#  whatsapp_missing_checked_at :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  contact_id    :bigint
#  inbox_id      :bigint
#  source_id     :text             not null
#
# Indexes
#
#  index_contact_inboxes_on_contact_id              (contact_id)
#  index_contact_inboxes_on_inbox_id                (inbox_id)
#  index_contact_inboxes_on_inbox_id_and_source_id  (inbox_id,source_id) UNIQUE
#  index_contact_inboxes_on_pubsub_token            (pubsub_token) UNIQUE
#  index_contact_inboxes_on_source_id               (source_id)
#

class ContactInbox < ApplicationRecord
  include Pubsubable
  include RegexHelper
  validates :inbox_id, presence: true
  validates :contact_id, presence: true
  validates :source_id, presence: true
  validate :valid_source_id_format?

  belongs_to :contact
  belongs_to :inbox

  has_many :conversations, dependent: :destroy_async

  # `whatsapp_missing_checked_at`: when a lookup found that this number has no WhatsApp (every
  # BR form said no). Messages to it get the server's single check and reach nobody, so the
  # conversation warns. Cleared by a lookup that finds the number, a message from the contact
  # or a live delivery/read receipt (see Message), and by a phone change or merge: the answer
  # was about the old number.
  before_update -> { self.whatsapp_missing_checked_at = nil }, if: :will_save_change_to_contact_id?
  after_update_commit :broadcast_whatsapp_missing_change, if: :saved_change_to_whatsapp_missing_checked_at?

  # contact_inboxes that are not associated with any conversation
  scope :stale_without_conversations, lambda { |time_period|
    left_joins(:conversations)
      .where('contact_inboxes.created_at < ?', time_period)
      .where(conversations: { contact_id: nil })
  }

  def webhook_data
    {
      id: id,
      contact: contact.try(:webhook_data),
      inbox: inbox.webhook_data,
      account: inbox.account.webhook_data,
      current_conversation: current_conversation.try(:webhook_data),
      source_id: source_id
    }
  end

  def current_conversation
    conversations.last
  end

  private

  # Tagged so the open thread does not jump to the bottom: no message arrived.
  def broadcast_whatsapp_missing_change
    conversations.find_each do |conversation|
      conversation.dispatch_conversation_updated_event(broadcast_metadata: { source: 'whatsapp_missing' })
    end
  end

  def validate_twilio_source_id
    # https://www.twilio.com/docs/glossary/what-e164#regex-matching-for-e164
    if inbox.channel.medium == 'sms' && !TWILIO_CHANNEL_SMS_REGEX.match?(source_id)
      errors.add(:source_id, "invalid source id for twilio sms inbox. valid Regex #{TWILIO_CHANNEL_SMS_REGEX}")
    elsif inbox.channel.medium == 'whatsapp' && !TWILIO_CHANNEL_WHATSAPP_REGEX.match?(source_id)
      errors.add(:source_id, "invalid source id for twilio whatsapp inbox. valid Regex #{TWILIO_CHANNEL_WHATSAPP_REGEX}")
    end
  end

  def validate_whatsapp_source_id
    return if WHATSAPP_CHANNEL_REGEX.match?(source_id)

    errors.add(:source_id, "invalid source id for whatsapp inbox. valid Regex #{WHATSAPP_CHANNEL_REGEX}")
  end

  def valid_source_id_format?
    validate_twilio_source_id if inbox.channel_type == 'Channel::TwilioSms'
    validate_whatsapp_source_id if inbox.channel_type == 'Channel::Whatsapp'
  end
end
