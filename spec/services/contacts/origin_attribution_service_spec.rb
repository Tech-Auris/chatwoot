require 'rails_helper'

RSpec.describe Contacts::OriginAttributionService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def perform(inbox:, message_body: '', referral: nil)
    described_class.new(
      contact: contact,
      inbox: inbox,
      message_body: message_body,
      referral: referral
    ).apply!
    contact.reload
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
end
