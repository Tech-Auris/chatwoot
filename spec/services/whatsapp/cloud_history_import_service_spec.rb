require 'rails_helper'

describe Whatsapp::CloudHistoryImportService do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', phone_number: '+5511900000000',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:patient_phone) { '5511988887777' }
  let(:three_days_ago) { 3.days.ago.change(usec: 0) }
  let(:two_days_ago) { 2.days.ago.change(usec: 0) }
  let(:messages) do
    [
      { from: patient_phone, id: 'wamid.in1', timestamp: three_days_ago.to_i.to_s, type: 'text', text: { body: 'Olá, quero agendar' } },
      { from: '5511900000000', id: 'wamid.out1', timestamp: two_days_ago.to_i.to_s, type: 'text', text: { body: 'Claro! Qual dia?' },
        history_context: { status: 'read' } }
    ]
  end
  let(:value) do
    {
      messaging_product: 'whatsapp',
      metadata: { display_phone_number: '5511900000000', phone_number_id: 'random_id' },
      history: [{ metadata: { phase: 0, chunk_order: 1, progress: 50 }, threads: [{ id: patient_phone, messages: messages }] }]
    }.with_indifferent_access
  end

  def import(payload = value)
    described_class.new(inbox: inbox, value: payload).perform
  end

  before { Current.reset }

  after { Current.reset }

  it 'imports the thread as a resolved conversation with the original dates and both directions' do
    import

    conversation = inbox.conversations.sole
    expect(conversation).to be_resolved
    expect(conversation.contact.phone_number).to eq("+#{patient_phone}")
    expect(conversation.created_at).to eq(three_days_ago)
    expect(conversation.last_activity_at).to eq(two_days_ago)

    incoming, outgoing = conversation.messages.order(:created_at).to_a
    expect([incoming.content, incoming.message_type, incoming.sender, incoming.created_at])
      .to eq(['Olá, quero agendar', 'incoming', conversation.contact, three_days_ago])
    expect([outgoing.content, outgoing.message_type, outgoing.sender, outgoing.created_at])
      .to eq(['Claro! Qual dia?', 'outgoing', nil, two_days_ago])
  end

  it 'does not reach the AI secretary, webhooks, automations or notifications' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    import

    [Events::Types::CONVERSATION_CREATED, Events::Types::MESSAGE_CREATED].each do |event|
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(event, anything, anything)
    end
  end

  it 'leaves the conversation resolved and unassigned when the inbox auto-assigns and has a bot' do
    agent = create(:user, account: inbox.account, role: :agent)
    create(:inbox_member, inbox: inbox, user: agent)
    inbox.update!(enable_auto_assignment: true)
    create(:agent_bot_inbox, inbox: inbox)

    import

    conversation = inbox.conversations.sole
    expect(conversation).to be_resolved
    expect(conversation.assignee).to be_nil
  end

  it 'does not duplicate messages when the same chunk arrives again' do
    import
    import

    expect(inbox.messages.count).to eq(2)
  end

  it 'adds the history to the contact conversation that already exists in the inbox' do
    contact = create(:contact, account: inbox.account, phone_number: "+#{patient_phone}")
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: patient_phone)
    existing = create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :open)

    import

    expect(inbox.conversations.sole).to eq(existing)
    expect(existing.reload).to be_open
    expect(existing.messages.where(source_id: %w[wamid.in1 wamid.out1]).count).to eq(2)
  end

  it 'drops messages older than 90 days before the history request' do
    channel.update_history_import_state!('requested_at' => 1.day.ago.iso8601)
    messages << { from: patient_phone, id: 'wamid.old', timestamp: 95.days.ago.to_i.to_s, type: 'text', text: { body: 'antiga' } }

    import

    expect(inbox.messages.pluck(:source_id)).to contain_exactly('wamid.in1', 'wamid.out1')
  end

  it 'tracks the progress and schedules the watchdog that completes the import' do
    expect { import }.to have_enqueued_job(Channels::Whatsapp::BaileysHistoryImportFinalizeJob)
      .with(channel.id, described_class::IDLE_WINDOW.to_i)

    state = channel.reload.history_import_state
    expect(state.slice('status', 'processed_batches', 'messages_imported'))
      .to eq('status' => 'in_progress', 'processed_batches' => 1, 'messages_imported' => 2)
  end

  it 'marks the import as declined when the business did not share its history' do
    import({ history: [{ errors: [{ code: 2_593_109, title: 'History sync is turned off by the business' }] }] }.with_indifferent_access)

    expect(channel.reload.history_import_state['status']).to eq('declined')
    expect(inbox.messages).to be_empty
  end

  describe 'media' do
    before do
      messages << { from: patient_phone, id: 'wamid.media1', timestamp: two_days_ago.to_i.to_s, type: 'media_placeholder' }
    end

    it 'imports a media message as a placeholder' do
      import

      message = inbox.messages.find_by(source_id: 'wamid.media1')
      expect(message.content).to eq(I18n.t('conversations.messages.whatsapp.history_media_unavailable'))
      expect(message.content_attributes['history_media_pending']).to be(true)
    end

    it 'attaches the file when Meta sends the media of a placeholder' do
      import
      stub_request(:get, %r{/media123}).to_return(
        status: 200, body: { url: 'https://lookaside.fbsbx.com/media123.jpg' }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
      stub_request(:get, 'https://lookaside.fbsbx.com/media123.jpg').to_return(
        status: 200, body: File.read('spec/assets/sample.png'), headers: { 'Content-Type' => 'image/png' }
      )

      import({ messages: [{ from: patient_phone, id: 'wamid.media1', timestamp: two_days_ago.to_i.to_s, type: 'image',
                            image: { id: 'media123', caption: 'Exame', mime_type: 'image/png' } }] }.with_indifferent_access)

      message = inbox.messages.find_by(source_id: 'wamid.media1')
      expect(message.content).to eq('Exame')
      expect(message.attachments.sole.file_type).to eq('image')
      expect(message.content_attributes).not_to have_key('history_media_pending')
    end
  end
end
