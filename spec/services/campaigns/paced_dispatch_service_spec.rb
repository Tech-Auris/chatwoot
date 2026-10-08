require 'rails_helper'

RSpec.describe Campaigns::PacedDispatchService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, cadence_seconds: 30) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def campaign_message(campaign_id: campaign.id)
    build(:message, account: account, inbox: inbox, conversation: conversation,
                    additional_attributes: { 'campaign_id' => campaign_id })
  end

  def persisted_campaign_message
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     additional_attributes: { 'campaign_id' => campaign.id })
  end

  describe '#perform' do
    # The campaign already creates one contact per cadence; each message then
    # leaves half an interval later, so creating and sending alternate.
    it 'sends the message half a cadence after it is created, on the campaign queue' do
      expect { described_class.new(message: campaign_message).perform }
        .to have_enqueued_job(SendReplyJob).on_queue('campaign').at(a_value_within(2.seconds).of(15.seconds.from_now))
    end

    it 'stamps when the message is going to be dispatched, for the campaign report' do
      message = persisted_campaign_message

      expect(message.reload.additional_attributes['campaign_dispatch_at']).to be_within(2).of(15.seconds.from_now.to_i)
    end

    it 'declines messages that do not belong to a campaign' do
      message = build(:message, account: account, inbox: inbox, conversation: conversation)

      expect(described_class.new(message: message).perform).to be false
    end

    it 'declines when the campaign was deleted after the message was built' do
      message = campaign_message(campaign_id: 0)

      expect(described_class.new(message: message).perform).to be false
    end
  end
end
