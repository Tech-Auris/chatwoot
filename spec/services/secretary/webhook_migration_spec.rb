require 'rails_helper'

RSpec.describe Secretary::WebhookMigration do
  let(:v32_url) { 'https://n8n.auris.ia.br/webhook/87dd35b4-4f1f-4d7e-ba01-ca6bab6b5816v3_2new' }
  let(:account) { create(:account) }
  let!(:reception) { create(:inbox, account: account) }
  let!(:sales) { create(:inbox, account: account) }
  let!(:webhook) { create(:webhook, account: account, inbox: nil, url: v32_url, subscriptions: ['message_created']) }

  it 'only reports the plan in a dry run' do
    rows = described_class.new.perform

    expect(rows.map(&:version_name)).to eq(['v3.2'])
    expect(rows.first.inbox_ids).to contain_exactly(reception.id, sales.id)
    expect(Webhook.exists?(webhook.id)).to be(true)
    expect(SecretaryVersion.count).to eq(0)
  end

  it 'moves the webhook into the account secretary config, keeping its secret' do
    described_class.new(apply: true).perform

    secretary = account.reload.account_secretary
    expect(secretary.secretary_version).to have_attributes(name: 'v3.2', webhook_url: v32_url)
    expect(secretary.secret).to eq(webhook.secret)
    expect([reception, sales].map { |inbox| inbox.reload.secretary_enabled }).to all(be(true))
    expect(Webhook.exists?(webhook.id)).to be(false)
  end

  it 'enables only the inbox the webhook was restricted to' do
    webhook.update!(inbox: sales)

    described_class.new(apply: true).perform

    expect(sales.reload.secretary_enabled).to be(true)
    expect(reception.reload.secretary_enabled).to be(false)
  end

  it 'leaves a suspended account without a secretary and drops its webhook' do
    account.update!(status: :suspended)

    described_class.new(apply: true).perform

    expect(account.reload.account_secretary.secretary_version).to be_nil
    expect(reception.reload.secretary_enabled).to be(false)
    expect(Webhook.exists?(webhook.id)).to be(false)
  end

  it 'does not touch other webhooks' do
    other = create(:webhook, account: account, url: 'https://n8n.auris.ia.br/webhook/funnel-listener')

    described_class.new(apply: true).perform

    expect(Webhook.exists?(other.id)).to be(true)
  end

  it 'is undone by the restore, with the same URL and secret' do
    webhook.update!(inbox: sales)
    described_class.new(apply: true).perform

    restored = Secretary::WebhookRestore.new.perform.first

    expect(restored).to have_attributes(url: v32_url, secret: webhook.secret, inbox_id: sales.id, subscriptions: ['message_created'])
    expect(account.reload.account_secretary.secretary_version).to be_nil
    expect(sales.reload.secretary_enabled).to be(false)
  end
end
