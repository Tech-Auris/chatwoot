# == Schema Information
#
# Table name: campaigns
#
#  id                                 :bigint           not null, primary key
#  audience                           :jsonb
#  audience_file_name                 :string
#  cadence_seconds                    :integer          default(10), not null
#  campaign_status                    :integer          default("active"), not null
#  campaign_type                      :integer          default("ongoing"), not null
#  conversation_label                 :string
#  description                        :text
#  enabled                            :boolean          default(TRUE)
#  failure_reason                     :string
#  message                            :text             not null
#  scheduled_at                       :datetime
#  template_params                    :jsonb            not null
#  title                              :string           not null
#  trigger_only_during_business_hours :boolean          default(FALSE)
#  trigger_rules                      :jsonb
#  created_at                         :datetime         not null
#  updated_at                         :datetime         not null
#  account_id                         :bigint           not null
#  creator_id                         :bigint
#  display_id                         :integer          not null
#  inbox_id                           :bigint           not null
#  sender_id                          :integer
#
# Indexes
#
#  index_campaigns_on_account_id       (account_id)
#  index_campaigns_on_campaign_status  (campaign_status)
#  index_campaigns_on_campaign_type    (campaign_type)
#  index_campaigns_on_inbox_id         (inbox_id)
#  index_campaigns_on_scheduled_at     (scheduled_at)
#
class Campaign < ApplicationRecord
  include UrlHelper

  MIN_CADENCE_SECONDS = 10

  validates :account_id, presence: true
  validates :inbox_id, presence: true
  validates :title, presence: true
  validates :message, presence: true
  # Floor of 10s so nothing — form, API or console — can queue a campaign that
  # bursts messages faster than the number's reputation tolerates.
  #
  # The value is validated for every campaign type, but only the one-off
  # WhatsApp flow spaces its sends by it today (see
  # Campaigns::PacedDispatchService). SMS campaigns still send inline, and
  # ongoing live chat campaigns fire one message per visitor, where delaying
  # would mean arriving after the visitor left the page.
  validates :cadence_seconds, numericality: { only_integer: true, greater_than_or_equal_to: MIN_CADENCE_SECONDS }
  validate :validate_campaign_inbox
  validate :validate_url
  validate :prevent_completed_campaign_from_update, on: :update
  validate :sender_must_belong_to_account
  validate :inbox_must_belong_to_account
  validate :whatsapp_number_must_be_able_to_send, on: :create

  belongs_to :account
  belongs_to :inbox
  belongs_to :sender, class_name: 'User', optional: true
  # Who created the campaign, told when it cannot go out. Unlike `sender`, it
  # does not sign the messages.
  belongs_to :creator, class_name: 'User', optional: true

  enum campaign_type: { ongoing: 0, one_off: 1 }
  # TODO : enabled attribute is unneccessary . lets move that to the campaign status with additional statuses like draft, disabled etc.
  enum campaign_status: { active: 0, completed: 1 }

  has_many :conversations, dependent: :nullify, autosave: true

  before_validation :ensure_correct_campaign_attributes
  after_commit :set_display_id, unless: :display_id?

  def trigger!
    return unless one_off?
    return if completed?

    execute_campaign
  end

  def push_event_data
    { id: id, display_id: display_id, title: title, inbox_id: inbox_id, failure_reason: failure_reason, meta: {} }
  end

  private

  def execute_campaign
    case inbox.inbox_type
    when 'Twilio SMS'
      Twilio::OneoffSmsCampaignService.new(campaign: self).perform
    when 'Sms'
      Sms::OneoffSmsCampaignService.new(campaign: self).perform
    when 'Whatsapp'
      return unless account.feature_enabled?(:whatsapp_campaign)
      return not_sent!(number_block_message) if number_block_message

      Whatsapp::OneoffCampaignService.new(campaign: self).perform
    end
  end

  # A campaign opens conversations, so a number that reached its new-contact
  # limit (RESTRICTED) cannot run one either.
  def number_block_message
    channel = inbox.channel
    channel.send_block_message(starts_conversation: true) if channel.respond_to?(:send_block_message)
  end

  def whatsapp_number_must_be_able_to_send
    return unless inbox&.inbox_type == 'Whatsapp'

    message = number_block_message
    errors.add(:base, message) if message
  end

  # The number broke down between scheduling and the start: the campaign does
  # not start, keeps the reason, and whoever created it is told.
  def not_sent!(reason)
    update!(campaign_status: :completed, failure_reason: reason)
    return if creator.blank?

    NotificationBuilder.new(notification_type: 'campaign_not_sent', user: creator, account: account, primary_actor: self).perform
  end

  def set_display_id
    reload
  end

  def validate_campaign_inbox
    return unless inbox

    errors.add :inbox, 'Unsupported Inbox type' unless ['Website', 'Twilio SMS', 'Sms', 'Whatsapp'].include? inbox.inbox_type
  end

  # TO-DO we clean up with better validations when campaigns evolve into more inboxes
  def ensure_correct_campaign_attributes
    return if inbox.blank?

    if ['Twilio SMS', 'Sms', 'Whatsapp'].include?(inbox.inbox_type)
      self.campaign_type = 'one_off'
      self.scheduled_at ||= Time.now.utc
    else
      self.campaign_type = 'ongoing'
      self.scheduled_at = nil
    end
  end

  def validate_url
    return unless trigger_rules['url']

    use_http_protocol = trigger_rules['url'].starts_with?('http://') || trigger_rules['url'].starts_with?('https://')
    errors.add(:url, 'invalid') if inbox.inbox_type == 'Website' && !use_http_protocol
  end

  def inbox_must_belong_to_account
    return unless inbox

    return if inbox.account_id == account_id

    errors.add(:inbox_id, 'must belong to the same account as the campaign')
  end

  def sender_must_belong_to_account
    return unless sender

    return if account.users.exists?(id: sender.id)

    errors.add(:sender_id, 'must belong to the same account as the campaign')
  end

  def prevent_completed_campaign_from_update
    errors.add :status, 'The campaign is already completed' if !campaign_status_changed? && completed?
  end

  # creating db triggers
  trigger.before(:insert).for_each(:row) do
    "NEW.display_id := nextval('camp_dpid_seq_' || NEW.account_id);"
  end
end
