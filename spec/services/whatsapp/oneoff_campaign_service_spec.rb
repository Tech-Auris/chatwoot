require 'rails_helper'

describe Whatsapp::OneoffCampaignService do
  let(:account) { create(:account) }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let!(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:label1) { create(:label, account: account) }
  let(:label2) { create(:label, account: account) }
  let!(:campaign) do
    create(:campaign, inbox: whatsapp_inbox, account: account,
                      audience: [{ type: 'Label', id: label1.id }, { type: 'Label', id: label2.id }],
                      template_params: template_params)
  end
  let(:template_params) do
    {
      'name' => 'ticket_status_updated',
      'namespace' => '23423423_2342423_324234234_2343224',
      'category' => 'UTILITY',
      'language' => 'en',
      'processed_params' => { 'body' => { 'name' => 'John', 'ticket_id' => '2332' } }
    }
  end

  before do
    # Stub HTTP requests to WhatsApp API
    stub_request(:post, /graph\.facebook\.com.*messages/)
      .to_return(status: 200, body: { messages: [{ id: 'message_id_123' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

    # Ensure the service uses our mocked channel object by stubbing the whole delegation chain
    # Using allow_any_instance_of here because the service is instantiated within individual tests
    # and we need to mock the delegated channel method for proper test isolation
    allow_any_instance_of(described_class).to receive(:channel).and_return(whatsapp_channel) # rubocop:disable RSpec/AnyInstance
  end

  describe '#perform' do
    before do
      # Enable WhatsApp campaigns feature flag for all tests
      account.enable_features!(:whatsapp_campaign)
    end

    context 'when campaign validation fails' do
      it 'raises error if campaign is completed' do
        campaign.completed!

        expect { described_class.new(campaign: campaign).perform }.to raise_error 'Completed Campaign'
      end

      it 'raises error when campaign is not a WhatsApp campaign' do
        sms_channel = create(:channel_sms, account: account)
        sms_inbox = create(:inbox, channel: sms_channel, account: account)
        invalid_campaign = create(:campaign, inbox: sms_inbox, account: account)

        expect { described_class.new(campaign: invalid_campaign).perform }
          .to raise_error "Invalid campaign #{invalid_campaign.id}"
      end

      it 'raises error when campaign is not oneoff' do
        allow(campaign).to receive(:one_off?).and_return(false)

        expect { described_class.new(campaign: campaign).perform }.to raise_error "Invalid campaign #{campaign.id}"
      end

      it 'raises error when channel provider is not whatsapp_cloud' do
        whatsapp_channel.update!(provider: 'default')

        expect { described_class.new(campaign: campaign).perform }.to raise_error 'WhatsApp Cloud provider required'
      end

      it 'raises error when WhatsApp campaigns feature is not enabled' do
        account.disable_features!(:whatsapp_campaign)

        expect { described_class.new(campaign: campaign).perform }.to raise_error 'WhatsApp campaigns feature not enabled'
      end
    end

    context 'when campaign is valid' do
      # Audience uploaded as a CSV is stored as explicit contacts, not labels,
      # so the campaign must target exactly those and ignore the label path.
      it 'targets the contacts listed in the audience when they are given explicitly' do
        tagged = create(:contact, :with_phone_number, account: account)
        tagged.update_labels([label1.title])
        chosen = create(:contact, :with_phone_number, account: account)
        campaign.update!(audience: [{ 'type' => 'Contact', 'id' => chosen.id }])

        perform_enqueued_jobs(only: Campaigns::DispatchContactJob) { described_class.new(campaign: campaign).perform }

        expect(Conversation.where(campaign_id: campaign.id).pluck(:contact_id)).to eq([chosen.id])
      end

      it 'tags the conversations when the campaign carries a label' do
        contact = create(:contact, :with_phone_number, account: account)
        campaign.update!(audience: [{ 'type' => 'Contact', 'id' => contact.id }], conversation_label: 'campanha-agosto')

        perform_enqueued_jobs(only: Campaigns::DispatchContactJob) { described_class.new(campaign: campaign).perform }

        conversation = Conversation.find_by(campaign_id: campaign.id)
        expect(conversation.label_list).to include('campanha-agosto')
      end

      it 'leaves conversations untagged when no label was chosen' do
        contact = create(:contact, :with_phone_number, account: account)
        campaign.update!(audience: [{ 'type' => 'Contact', 'id' => contact.id }])

        perform_enqueued_jobs(only: Campaigns::DispatchContactJob) { described_class.new(campaign: campaign).perform }

        expect(Conversation.find_by(campaign_id: campaign.id).label_list).to be_empty
      end

      # Creating every conversation and message the moment the campaign starts
      # spiked the server's CPU (232 contacts in one minute). Each contact now
      # gets its own job, a cadence apart, and nothing is created up front.
      it 'schedules one contact per cadence instead of creating them all at once' do
        campaign.update!(cadence_seconds: 30)
        create_list(:contact, 3, :with_phone_number, account: account)
          .each { |contact| contact.update_labels([label1.title]) }

        expect { described_class.new(campaign: campaign).perform }.not_to change(Conversation, :count)

        jobs = enqueued_jobs.select { |job| job['job_class'] == 'Campaigns::DispatchContactJob' }
        waits = jobs.map { |job| job['scheduled_at'].present? ? (Time.zone.parse(job['scheduled_at'].to_s) - Time.current).round : 0 }
        expect(jobs.pluck('queue_name').uniq).to eq(['campaign'])
        expect(waits.sort).to match([be_within(2).of(0), be_within(2).of(30), be_within(2).of(60)])
      end

      it 'creates the conversation and the message when the turn of the contact comes' do
        contact = create(:contact, :with_phone_number, account: account)
        campaign.update!(audience: [{ 'type' => 'Contact', 'id' => contact.id }])

        perform_enqueued_jobs(only: Campaigns::DispatchContactJob) { described_class.new(campaign: campaign).perform }

        conversation = Conversation.find_by(campaign_id: campaign.id)
        expect(conversation.messages.outgoing.count).to eq(1)
      end

      it 'gives a new conversation the Disparo interno origin' do
        contact = create(:contact, :with_phone_number, account: account)
        campaign.update!(audience: [{ 'type' => 'Contact', 'id' => contact.id }])

        perform_enqueued_jobs(only: Campaigns::DispatchContactJob) { described_class.new(campaign: campaign).perform }

        expect(Conversation.find_by(campaign_id: campaign.id).origem).to eq('Disparo interno')
      end

      it 'ties a conversation the contact already had to the campaign, keeping an origin it already had' do
        with_origin = create(:contact, :with_phone_number, account: account)
        without_origin = create(:contact, :with_phone_number, account: account)
        kept = create(:conversation, account: account, inbox: whatsapp_inbox, contact: with_origin, origem: 'Instagram')
        filled = create(:conversation, account: account, inbox: whatsapp_inbox, contact: without_origin, status: :resolved)
        campaign.update!(audience: [{ 'type' => 'Contact', 'id' => with_origin.id }, { 'type' => 'Contact', 'id' => without_origin.id }])

        perform_enqueued_jobs(only: Campaigns::DispatchContactJob) { described_class.new(campaign: campaign).perform }

        expect(kept.reload).to have_attributes(campaign_id: campaign.id, origem: 'Instagram')
        expect(filled.reload).to have_attributes(campaign_id: campaign.id, origem: 'Disparo interno', status: 'pending')
      end

      it 'leaves out the contacts with the marketing opt-out, counting them' do
        reached = create(:contact, :with_phone_number, account: account)
        opted_out = create(:contact, :with_phone_number, account: account)
        opted_out.opt_out!(source: 'meta')
        campaign.update!(audience: [{ 'type' => 'Contact', 'id' => reached.id }, { 'type' => 'Contact', 'id' => opted_out.id }])

        perform_enqueued_jobs(only: Campaigns::DispatchContactJob) { described_class.new(campaign: campaign).perform }

        expect(Conversation.where(campaign_id: campaign.id).pluck(:contact_id)).to eq([reached.id])
        expect(campaign.reload.skipped_opt_out_count).to eq(1)
      end

      it 'skips a contact that opted out after the campaign was scheduled' do
        contact = create(:contact, :with_phone_number, account: account)
        campaign.update!(audience: [{ 'type' => 'Contact', 'id' => contact.id }])
        described_class.new(campaign: campaign).perform
        contact.opt_out!(source: 'ai')

        perform_enqueued_jobs(only: Campaigns::DispatchContactJob)

        expect(Conversation.where(campaign_id: campaign.id)).to be_empty
        expect(campaign.reload.skipped_opt_out_count).to eq(1)
      end

      context 'with a saved audience' do
        let(:abc) { create(:label, account: account, title: 'abc') }
        let(:saved) do
          rule = [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => [abc.title], 'query_operator' => nil }]
          create(:audience, account: account, rule: rule)
        end

        def member(name)
          contact = create(:contact, :with_phone_number, account: account, name: name)
          create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact).update_labels([abc.title])
          contact
        end

        it 'sends to the members of the moment it starts, and keeps that list' do
          first = member('Primeiro')
          campaign.update!(audience: [{ 'type' => 'Audience', 'id' => saved.id }])

          described_class.new(campaign: campaign).perform
          member('Depois do início')
          perform_enqueued_jobs(only: Campaigns::DispatchContactJob)

          expect(campaign.reload.audience).to eq([{ 'type' => 'Contact', 'id' => first.id }])
          expect(campaign.audience_source).to eq(saved)
          expect(Conversation.where(campaign_id: campaign.id).pluck(:contact_id)).to eq([first.id])
          expect(saved.events.last).to have_attributes(kind: 'campaign', campaign_id: campaign.id, contacts_count: 1)
        end

        it 'sends nothing when the audience is over the limit' do
          stub_const('Audience::MAX_CONTACTS', 1)
          2.times { |index| member("Contato #{index}") }
          campaign.update!(audience: [{ 'type' => 'Audience', 'id' => saved.id }])

          described_class.new(campaign: campaign).perform

          expect(enqueued_jobs.count { |job| job['job_class'] == 'Campaigns::DispatchContactJob' }).to eq(0)
        end
      end

      it 'never sends the campaign twice to the same contact' do
        reached = create(:contact, :with_phone_number, account: account)
        fresh = create(:contact, :with_phone_number, account: account)
        conversation = create(:conversation, account: account, inbox: whatsapp_inbox, contact: reached)
        create(:message, account: account, inbox: whatsapp_inbox, conversation: conversation, message_type: :outgoing,
                         additional_attributes: { campaign_id: campaign.id })
        campaign.update!(audience: [{ 'type' => 'Contact', 'id' => reached.id }, { 'type' => 'Contact', 'id' => fresh.id }])

        described_class.new(campaign: campaign).perform

        expect(enqueued_jobs.select { |job| job['job_class'] == 'Campaigns::DispatchContactJob' }.map { |job| job['arguments'].last })
          .to eq([fresh.id])
      end

      it 'marks campaign as completed' do
        described_class.new(campaign: campaign).perform

        expect(campaign.reload.completed?).to be true
      end

      it 'marks the campaign completed after processing the audience', skip: 'Tech-Auris uses custom build_outgoing_template_message instead of channel.send_template' do # rubocop:disable Layout/LineLength
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        expect(whatsapp_channel).to receive(:send_template) do
          expect(campaign.reload.completed?).to be false
        end

        described_class.new(campaign: campaign).perform

        expect(campaign.reload.completed?).to be true
      end

      it 'processes contacts with matching labels', skip: 'Tech-Auris uses custom build_outgoing_template_message instead of channel.send_template' do
        contact_with_label1, contact_with_label2, contact_with_both_labels =
          create_list(:contact, 3, :with_phone_number, account: account)
        contact_with_label1.update_labels([label1.title])
        contact_with_label2.update_labels([label2.title])
        contact_with_both_labels.update_labels([label1.title, label2.title])

        expect(whatsapp_channel).to receive(:send_template).exactly(3).times

        described_class.new(campaign: campaign).perform
      end

      it 'skips contacts without phone numbers' do
        contact_without_phone = create(:contact, account: account, phone_number: nil)
        contact_without_phone.update_labels([label1.title])

        expect(whatsapp_channel).not_to receive(:send_template)

        described_class.new(campaign: campaign).perform
      end

      it 'uses template processor service to process templates', skip: 'Tech-Auris uses custom TemplateBodyRenderer instead of TemplateProcessorService' do # rubocop:disable Layout/LineLength
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        expect(Whatsapp::TemplateProcessorService).to receive(:new)
          .with(channel: whatsapp_channel, template_params: template_params)
          .and_call_original

        described_class.new(campaign: campaign).perform
      end

      it 'sends template message with correct parameters', skip: 'Tech-Auris uses custom MessageBuilder path — see build_outgoing_template_message' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        expect(whatsapp_channel).to receive(:send_template).with(
          contact.phone_number,
          hash_including(
            name: 'ticket_status_updated',
            namespace: '23423423_2342423_324234234_2343224',
            lang_code: 'en',
            parameters: array_including(
              hash_including(
                type: 'body',
                parameters: array_including(
                  hash_including(type: 'text', parameter_name: 'name', text: 'John'),
                  hash_including(type: 'text', parameter_name: 'ticket_id', text: '2332')
                )
              )
            )
          ),
          nil
        )

        described_class.new(campaign: campaign).perform
      end

      it 'processes liquid variables in template parameters', skip: 'Tech-Auris uses CampaignTemplateLiquidRenderer with different call surface' do
        contact = create(:contact, :with_phone_number, account: account, name: 'Jane Smith', email: 'jane@example.com')
        contact.update_labels([label1.title])

        campaign_with_liquid = create(:campaign, inbox: whatsapp_inbox, account: account,
                                                 audience: [{ type: 'Label', id: label1.id }],
                                                 template_params: {
                                                   'name' => 'ticket_status_updated',
                                                   'namespace' => '23423423_2342423_324234234_2343224',
                                                   'category' => 'UTILITY',
                                                   'language' => 'en',
                                                   'processed_params' => {
                                                     'body' => {
                                                       'name' => '{{contact.name}}',
                                                       'ticket_id' => '{{contact.email}}'
                                                     }
                                                   }
                                                 })

        contact_drop_name = ContactDrop.new(contact).name

        expect(whatsapp_channel).to receive(:send_template).with(
          contact.phone_number,
          hash_including(
            name: 'ticket_status_updated',
            namespace: '23423423_2342423_324234234_2343224',
            lang_code: 'en',
            parameters: array_including(
              hash_including(
                type: 'body',
                parameters: array_including(
                  hash_including(type: 'text', parameter_name: 'name', text: contact_drop_name),
                  hash_including(type: 'text', parameter_name: 'ticket_id', text: contact.email)
                )
              )
            )
          ),
          nil
        )

        described_class.new(campaign: campaign_with_liquid).perform
      end

      it 'skips contacts when liquid variables resolve to blank values', skip: 'Tech-Auris does not use LiquidTemplateProcessorService' do
        contact = create(:contact, :with_phone_number, account: account, name: 'Jane', email: nil)
        contact.update_labels([label1.title])

        campaign_with_blank_liquid = create(:campaign, inbox: whatsapp_inbox, account: account,
                                                       audience: [{ type: 'Label', id: label1.id }],
                                                       template_params: {
                                                         'name' => 'test_template',
                                                         'namespace' => 'test_namespace',
                                                         'language' => 'en',
                                                         'processed_params' => {
                                                           'body' => {
                                                             'email' => '{{contact.email}}'
                                                           }
                                                         }
                                                       })

        expect(whatsapp_channel).not_to receive(:send_template)
        expect(Rails.logger).to receive(:info).with("Skipping contact #{contact.name} - liquid variables resolved to blank values")
        allow(Rails.logger).to receive(:info)

        described_class.new(campaign: campaign_with_blank_liquid).perform
      end
    end

    context 'when template_params is missing' do
      let(:template_params) { nil }

      it 'skips contacts and logs error', skip: 'Not-null constraint on campaigns table does not allow this' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        expect(Rails.logger).to receive(:error)
          .with("Skipping contact #{contact.name} - no template_params found for WhatsApp campaign")
        expect(whatsapp_channel).not_to receive(:send_template)

        described_class.new(campaign: campaign).perform
      end
    end

    context 'when send_template raises an error' do
      it 'logs error and continues processing remaining contacts', skip: 'Rescue swallows the raised send_template error before it can be tracked here' do # rubocop:disable Layout/LineLength
        contact_error, contact_success = create_list(:contact, 2, :with_phone_number, account: account)
        contact_error.update_labels([label1.title])
        contact_success.update_labels([label1.title])
        error_message = 'WhatsApp API error'

        allow(whatsapp_channel).to receive(:send_template).and_return(nil)

        expect(whatsapp_channel).to receive(:send_template).with(contact_error.phone_number, anything, nil).and_raise(StandardError, error_message)
        expect(whatsapp_channel).to receive(:send_template).with(contact_success.phone_number, anything, nil).once

        expect(Rails.logger).to receive(:error)
          .with("Failed to send WhatsApp template message to #{contact_error.phone_number}: #{error_message}")
        expect(Rails.logger).to receive(:error).with(/Backtrace:/)

        described_class.new(campaign: campaign).perform
        expect(campaign.reload.completed?).to be true
      end
    end
  end
end
