require 'rails_helper'

RSpec.describe Contacts::OriginAttributionService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def perform(inbox:, message_body: '', referral: nil, conversation: nil)
    described_class.new(
      contact: contact,
      inbox: inbox,
      conversation: conversation,
      message_body: message_body,
      referral: referral
    ).apply!
    contact.reload
    conversation&.reload
  end

  describe '#apply!' do
    let(:whatsapp_inbox) do
      create(:inbox, account: account, channel: create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false))
    end

    it 'sets Google when the first message body carries a gclid token' do
      perform(inbox: whatsapp_inbox, message_body: 'Ola, quero saber sobre gclid=Cj0-abc')

      expect(contact.additional_attributes['origem']).to eq('Google')
    end

    # Referral payload takes priority over channel-based inference — a WA
    # inbound that came from a Meta ad is what "Anúncio de Origem" means.
    it 'sets Facebook when the CTWA referral source_url points to fb.me' do
      perform(inbox: whatsapp_inbox, referral: { 'source_url' => 'https://fb.me/xyz', 'source_id' => '1' })

      expect(contact.additional_attributes['origem']).to eq('Facebook')
    end

    it 'sets Instagram when the referral source_url points to Instagram' do
      perform(inbox: whatsapp_inbox, referral: { 'source_url' => 'https://ig.me/xyz', 'source_id' => '1' })

      expect(contact.additional_attributes['origem']).to eq('Instagram')
    end

    it 'sets Facebook when the inbox is a Facebook Page (Messenger)' do
      stub_request(:post, /graph.facebook.com/)
      fb_inbox = create(:inbox, account: account, channel: create(:channel_facebook_page, account: account))
      perform(inbox: fb_inbox)

      expect(contact.additional_attributes['origem']).to eq('Facebook')
    end

    it 'sets Instagram when the inbox is a direct Instagram channel' do
      ig_inbox = create(:inbox, account: account, channel: create(:channel_instagram, account: account))
      perform(inbox: ig_inbox)

      expect(contact.additional_attributes['origem']).to eq('Instagram')
    end

    # Absence of any signal is on purpose left as "Sem Origem" — we do not
    # want to claim Orgânico for a contact that might have come from an
    # unmapped source. The operator fills it in manually.
    it 'leaves origem unset when no signal is present on a WA inbound' do
      perform(inbox: whatsapp_inbox)

      expect(contact.additional_attributes['origem']).to be_nil
    end

    # The operator's manual choice is authoritative; a new inbound must not
    # rewrite what a human already decided about this contact.
    it 'does not overwrite an origem that is already set' do
      contact.update!(additional_attributes: { 'origem' => 'Indicação de cliente' })

      perform(inbox: whatsapp_inbox, referral: { 'source_url' => 'https://fb.me/xyz', 'source_id' => '1' })

      expect(contact.additional_attributes['origem']).to eq('Indicação de cliente')
    end
  end

  # PR 1 of the origem-on-conversation migration: the service dual-writes to
  # both Contact.additional_attributes.origem (legacy, still read) and the new
  # Conversation.origem column. Follow-up PRs flip readers to the conversation
  # and eventually drop the contact write.
  describe '#apply! (conversation dual-write)' do
    let(:whatsapp_inbox) do
      create(:inbox, account: account, channel: create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false))
    end
    let(:conversation) { create(:conversation, account: account, contact: contact, inbox: whatsapp_inbox) }

    it 'writes the same value to Conversation.origem when a conversation is given' do
      perform(inbox: whatsapp_inbox, conversation: conversation, message_body: 'gclid=abc-123')

      expect(conversation.origem).to eq('Google')
      expect(contact.additional_attributes['origem']).to eq('Google')
    end

    # First-touch per conversation mirrors the guard on Contact — a later
    # inbound on the same conversation with a fresh referral must not
    # overwrite the origem that opened it.
    it 'does not overwrite Conversation.origem once it is set' do
      conversation.update!(origem: 'Indicação de colega')

      perform(inbox: whatsapp_inbox, conversation: conversation, referral: { 'source_url' => 'https://fb.me/xyz', 'source_id' => '1' })

      expect(conversation.origem).to eq('Indicação de colega')
    end

    # The two writes are independent: a legacy contact that already has origem
    # can still seed a fresh conversation on this inbound.
    it 'still populates a fresh Conversation.origem even when Contact.origem is already set' do
      contact.update!(additional_attributes: { 'origem' => 'Evento' })

      perform(inbox: whatsapp_inbox, conversation: conversation, message_body: 'gclid=abc-123')

      expect(conversation.origem).to eq('Google')
      expect(contact.additional_attributes['origem']).to eq('Evento')
    end

    it 'is a no-op when no conversation is passed (Contact write stays)' do
      perform(inbox: whatsapp_inbox, message_body: 'gclid=abc-123')

      expect(conversation.origem).to be_nil
      expect(contact.additional_attributes['origem']).to eq('Google')
    end

    it 'leaves Conversation.origem null when no signal is present' do
      perform(inbox: whatsapp_inbox, conversation: conversation)

      expect(conversation.origem).to be_nil
    end
  end
end
