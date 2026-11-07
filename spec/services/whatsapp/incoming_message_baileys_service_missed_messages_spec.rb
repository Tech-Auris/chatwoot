require 'rails_helper'

# After a reconnect WhatsApp replays what arrived while the connection was down. Those
# messages exist nowhere else, so they must reach the inbox as live traffic, whether the
# inbox imports history (batches with `importMode`) or not (`messaging-history.set` frames).
describe Whatsapp::IncomingMessageBaileysService do
  let(:webhook_verify_token) { 'valid_token' }
  let(:history_import_days) { 0 }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'baileys', validate_provider_config: false, received_messages: false,
                              provider_config: { webhook_verify_token: webhook_verify_token, history_import_days: history_import_days })
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:disconnected_at) { 2.hours.ago.change(usec: 0) }

  def raw_message(id, sent_at, text: 'Olá', jid: '5511999999999@s.whatsapp.net')
    { key: { id: id, remoteJid: jid, fromMe: false }, pushName: 'Paciente', messageTimestamp: sent_at.to_i, message: { conversation: text } }
  end

  def deliver(event, data, **extra)
    described_class.new(inbox: inbox, params: { webhookVerifyToken: webhook_verify_token, event: event, data: data, **extra }).perform
  end

  def reconnect
    deliver('connection.update', { connection: 'close' })
    deliver('connection.update', { connection: 'open' })
  end

  before do
    stub_request(:get, /profile-picture-url/).to_return(status: 200, body: { data: { profilePictureUrl: nil } }.to_json)
    stub_request(:post, %r{/on-whatsapp}).to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
    Current.reset
  end

  after { Current.reset }

  describe 'what the inbox was covering when the connection came back' do
    it 'is the newest message it held, read as the connection opens' do
      deliver('messages.upsert', { type: 'notify', messages: [raw_message('live_1', disconnected_at)] })
      inbox.messages.find_by(source_id: 'live_1').update!(created_at: disconnected_at)

      reconnect

      expect(Time.zone.parse(whatsapp_channel.reload.provider_connection['coverage_until'])).to eq(disconnected_at)
    end

    it 'is unknown on a first pairing, so nothing counts as missed' do
      deliver('connection.update', { connection: 'open' })

      expect(whatsapp_channel.reload.provider_connection['coverage_until']).to be_nil
    end
  end

  context 'with a reconnected inbox that holds earlier messages' do
    before do
      deliver('messages.upsert', { type: 'notify', messages: [raw_message('live_1', disconnected_at)] })
      inbox.messages.find_by(source_id: 'live_1').update!(created_at: disconnected_at)
      reconnect
    end

    it 'files what arrived while disconnected as live messages, and leaves older history out' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      deliver('messaging-history.set', { syncType: 3, chunkIndex: 0,
                                         messages: [raw_message('old_1', 1.day.ago), raw_message('missed_1', 1.hour.ago, text: 'Oi?')] })

      expect(inbox.messages.pluck(:source_id)).to contain_exactly('live_1', 'missed_1')
      missed = inbox.messages.find_by(source_id: 'missed_1')
      expect(missed.conversation).to be_open
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(Events::Types::MESSAGE_CREATED, anything,
                                                                              hash_including(message: missed))
    end

    it 'does not file a missed message twice when it also arrived live' do
      deliver('messages.upsert', { type: 'notify', messages: [raw_message('missed_1', 1.hour.ago)] })

      deliver('messaging-history.set', { syncType: 3, messages: [raw_message('missed_1', 1.hour.ago)] })

      expect(inbox.messages.where(source_id: 'missed_1').count).to eq(1)
    end

    context 'when the inbox imports history' do
      let(:history_import_days) { 7 }

      it 'takes the missed messages out of the import, so they are answered' do
        allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

        deliver('messages.upsert', { type: 'notify', messages: [raw_message('old_1', 3.days.ago), raw_message('missed_1', 1.hour.ago)] },
                importMode: true, importBatch: { index: 0, total: 1, phase: 'history' })

        old, missed = inbox.messages.where(source_id: %w[old_1 missed_1]).order(:created_at).to_a
        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(Events::Types::MESSAGE_CREATED, anything,
                                                                                hash_including(message: missed))
        expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::MESSAGE_CREATED, anything,
                                                                                    hash_including(message: old))
      end
    end
  end

  context 'when a pairing imports history' do
    let(:history_import_days) { 7 }
    let(:import) { { importMode: true, importBatch: { index: 0, total: 1, phase: 'history' } } }

    it 'files each message and its conversation with the date it was sent' do
      first_sent = 3.days.ago.change(usec: 0)
      last_sent = 2.days.ago.change(usec: 0)

      deliver('messages.upsert', { type: 'notify', messages: [raw_message('old_1', first_sent), raw_message('old_2', last_sent)] }, **import)

      conversation = inbox.conversations.sole
      expect(conversation).to be_resolved
      expect([conversation.created_at, conversation.last_activity_at]).to eq([first_sent, last_sent])
      expect(inbox.messages.order(:created_at).pluck(:created_at)).to eq([first_sent, last_sent])
    end

    it 'keeps a contact in one conversation when the inbox opens a new one after resolving' do
      inbox.update!(lock_to_single_conversation: false)

      deliver('messages.upsert', { type: 'notify', messages: [raw_message('old_1', 3.days.ago), raw_message('old_2', 2.days.ago)] }, **import)

      expect(inbox.conversations.count).to eq(1)
    end
  end
end
