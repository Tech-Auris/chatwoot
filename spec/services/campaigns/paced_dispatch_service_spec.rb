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

  before { Redis::Alfred.delete("campaign_dispatch_position:#{campaign.id}") }

  describe '#perform' do
    it 'sends the first message of a campaign immediately' do
      expect { described_class.new(message: campaign_message).perform }
        .to have_enqueued_job(SendReplyJob).on_queue('campaign').at(:no_wait)
    end

    # The whole point: each message waits one more interval than the previous
    # one, so the rhythm holds regardless of how many workers are free.
    it 'spaces each following message by the campaign cadence' do
      described_class.new(message: campaign_message).perform

      expect { described_class.new(message: campaign_message).perform }
        .to have_enqueued_job(SendReplyJob).on_queue('campaign').at(a_value_within(5.seconds).of(30.seconds.from_now))

      expect { described_class.new(message: campaign_message).perform }
        .to have_enqueued_job(SendReplyJob).on_queue('campaign').at(a_value_within(5.seconds).of(60.seconds.from_now))
    end

    it 'counts positions per campaign, so one campaign does not delay another' do
      other = create(:campaign, account: account, inbox: inbox, cadence_seconds: 30)
      Redis::Alfred.delete("campaign_dispatch_position:#{other.id}")
      described_class.new(message: campaign_message).perform

      expect { described_class.new(message: campaign_message(campaign_id: other.id)).perform }
        .to have_enqueued_job(SendReplyJob).on_queue('campaign').at(:no_wait)
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
