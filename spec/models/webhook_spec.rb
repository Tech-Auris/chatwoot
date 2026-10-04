require 'rails_helper'

RSpec.describe Webhook do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:account_id) }

    it 'rejects the URL of a secretary version, so the secretary never answers twice' do
      version = create(:secretary_version)
      webhook = build(:webhook, url: version.webhook_url)

      expect(webhook).not_to be_valid
      expect(webhook.errors[:url]).to be_present
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
  end

  describe 'inboxes' do
    let(:account) { create(:account) }
    let(:reception) { create(:inbox, account: account) }
    let(:sales) { create(:inbox, account: account) }

    it 'delivers for every inbox when none is picked' do
      webhook = create(:webhook, account: account)

      expect(webhook.delivers_for_inbox?(reception.id)).to be(true)
    end

    it 'delivers only for the picked inboxes' do
      webhook = create(:webhook, account: account, inbox_ids: [reception.id])

      expect(webhook.delivers_for_inbox?(reception.id)).to be(true)
      expect(webhook.delivers_for_inbox?(sales.id)).to be(false)
    end

    it 'drops a deleted inbox from the list and keeps the others' do
      webhook = create(:webhook, account: account, inbox_ids: [reception.id, sales.id])

      reception.destroy!

      expect(webhook.reload.inbox_ids).to eq([sales.id])
    end

    # An empty list would mean "every inbox", widening what the webhook receives.
    it 'is deleted with its only inbox instead of falling back to every inbox' do
      webhook = create(:webhook, account: account, inbox_ids: [reception.id])

      reception.destroy!

      expect(described_class.exists?(webhook.id)).to be(false)
    end
  end

  describe 'secret token' do
    let!(:account) { create(:account) }

    it 'auto-generates a secret on create' do
      webhook = create(:webhook, account: account)
      expect(webhook.secret).to be_present
    end

    it 'does not regenerate the secret on update' do
      webhook = create(:webhook, account: account)
      original_secret = webhook.secret
      webhook.update!(url: "#{webhook.url}?updated=1")
      expect(webhook.reload.secret).to eq(original_secret)
    end
  end
end
