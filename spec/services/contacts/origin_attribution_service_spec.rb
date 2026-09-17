require 'rails_helper'

RSpec.describe Contacts::OriginAttributionService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:whatsapp_inbox) do
    create(:inbox, account: account, channel: create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false))
  end
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: whatsapp_inbox) }

  def perform(inbox:, conversation:, message_body: '', referral: nil)
    described_class.new(
      inbox: inbox,
      conversation: conversation,
      message_body: message_body,
      referral: referral
    ).apply!
    conversation.reload
  end

  describe '#apply!' do
    it 'sets Google when the first message body carries a gclid token' do
      perform(inbox: whatsapp_inbox, conversation: conversation, message_body: 'Ola, quero saber sobre gclid=Cj0-abc')

      expect(conversation.origem).to eq('Google')
    end

    # Referral payload takes priority over channel-based inference — a WA
    # inbound that came from a Meta ad is what "Anúncio de Origem" means.
    it 'sets Facebook when the CTWA referral source_url points to fb.me' do
      perform(inbox: whatsapp_inbox, conversation: conversation, referral: { 'source_url' => 'https://fb.me/xyz', 'source_id' => '1' })

      expect(conversation.origem).to eq('Facebook')
    end

    it 'sets Instagram when the referral source_url points to Instagram' do
      perform(inbox: whatsapp_inbox, conversation: conversation, referral: { 'source_url' => 'https://ig.me/xyz', 'source_id' => '1' })

      expect(conversation.origem).to eq('Instagram')
    end

    it 'sets Facebook when the inbox is a Facebook Page (Messenger)' do
      stub_request(:post, /graph.facebook.com/)
      fb_inbox = create(:inbox, account: account, channel: create(:channel_facebook_page, account: account))
      fb_conversation = create(:conversation, account: account, contact: contact, inbox: fb_inbox)
      perform(inbox: fb_inbox, conversation: fb_conversation)

      expect(fb_conversation.origem).to eq('Facebook')
    end

    it 'sets Instagram when the inbox is a direct Instagram channel' do
      ig_inbox = create(:inbox, account: account, channel: create(:channel_instagram, account: account))
      ig_conversation = create(:conversation, account: account, contact: contact, inbox: ig_inbox)
      perform(inbox: ig_inbox, conversation: ig_conversation)

      expect(ig_conversation.origem).to eq('Instagram')
    end

    # Absence of any signal is on purpose left as "Sem Origem" — we do not
    # want to claim Orgânico for a conversation that might have come from an
    # unmapped source. The operator fills it in manually.
    it 'leaves origem unset when no signal is present on a WA inbound' do
      perform(inbox: whatsapp_inbox, conversation: conversation)

      expect(conversation.origem).to be_nil
    end

    # First-touch per conversation — the operator's manual selection (or a
    # previous inbound's signal) sticks, so a later inbound on the same
    # conversation must not overwrite the origem that opened it.
    it 'does not overwrite an origem that is already set on the conversation' do
      conversation.update!(origem: 'Indicação de cliente')

      perform(inbox: whatsapp_inbox, conversation: conversation, referral: { 'source_url' => 'https://fb.me/xyz', 'source_id' => '1' })

      expect(conversation.origem).to eq('Indicação de cliente')
    end

    # Two different conversations of the SAME contact can capture different
    # origens — the guard is per-conversation, not per-contact.
    it 'lets a fresh conversation of the same contact capture its own origem' do
      conversation.update!(origem: 'Facebook')
      another = create(:conversation, account: account, contact: contact, inbox: whatsapp_inbox)

      perform(inbox: whatsapp_inbox, conversation: another, message_body: 'gclid=abc')

      expect(another.origem).to eq('Google')
      expect(conversation.reload.origem).to eq('Facebook')
    end
  end
end
