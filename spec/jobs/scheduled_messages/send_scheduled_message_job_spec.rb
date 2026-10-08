require 'rails_helper'

RSpec.describe ScheduledMessages::SendScheduledMessageJob, type: :job do
  let(:account) { create(:account) }
  let(:author) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:scheduled_message) { create(:scheduled_message, account: account, inbox: inbox, conversation: conversation, author: author) }

  describe '#perform' do
    it 'creates message with metadata and marks as sent' do
      travel_to(3.minutes.from_now) do
        described_class.new.perform(scheduled_message.id)

        message = conversation.messages.last
        expect(message.content).to eq(scheduled_message.content)
        expect(message.additional_attributes['scheduled_message_id']).to eq(scheduled_message.id)
        expect(message.additional_attributes['scheduled_by']).to include('id' => author.id, 'type' => 'User')
        expect(scheduled_message.reload.status).to eq('sent')
      end
    end

    it 'sets automation_rule_id when author is AutomationRule' do
      automation_rule = create(:automation_rule, account: account)
      scheduled_message = create(:scheduled_message, account: account, inbox: inbox, conversation: conversation, author: automation_rule)

      travel_to(3.minutes.from_now) do
        described_class.new.perform(scheduled_message.id)

        message = conversation.messages.last
        expect(message.content_attributes['automation_rule_id']).to eq(automation_rule.id)
        expect(message.additional_attributes['scheduled_by']).to include('id' => automation_rule.id, 'type' => 'AutomationRule')
      end
    end

    it 'includes template_params when present' do
      template_params = { 'name' => 'sample_template', 'language' => 'en' }
      scheduled_message = create(:scheduled_message, account: account, inbox: inbox, conversation: conversation, author: author, content: nil,
                                                     template_params: template_params)

      travel_to(3.minutes.from_now) do
        described_class.new.perform(scheduled_message.id)

        expect(conversation.messages.last.additional_attributes['template_params']).to eq(template_params)
      end
    end

    it 'includes attachment when present' do
      file = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png')
      scheduled_message = create(:scheduled_message, account: account, inbox: inbox, conversation: conversation, author: author, content: nil,
                                                     attachment: file)

      travel_to(3.minutes.from_now) do
        described_class.new.perform(scheduled_message.id)

        expect(conversation.messages.last.attachments.count).to eq(1)
      end
    end

    it 'marks as failed on error' do
      allow(Messages::MessageBuilder).to receive(:new).and_raise(StandardError, 'boom')

      travel_to(3.minutes.from_now) do
        described_class.new.perform(scheduled_message.id)

        expect(scheduled_message.reload.status).to eq('failed')
      end
    end

    it 'skips when not pending' do
      draft = create(:scheduled_message, account: account, inbox: inbox, conversation: conversation, author: author, status: :draft,
                                         scheduled_at: nil)

      travel_to(3.minutes.from_now) do
        expect { described_class.new.perform(draft.id) }.not_to(change { conversation.messages.count })
      end
    end

    it 'skips when not due' do
      future = create(:scheduled_message, account: account, inbox: inbox, conversation: conversation, author: author,
                                          scheduled_at: 10.minutes.from_now)

      travel_to(3.minutes.from_now) do
        expect { described_class.new.perform(future.id) }.not_to(change { conversation.messages.count })
      end
    end

    context 'when the WhatsApp number cannot send at the scheduled time' do
      let(:channel) do
        create(:channel_whatsapp, account: account, provider: 'baileys', provider_connection: { 'connection' => 'close' },
                                  sync_templates: false, validate_provider_config: false)
      end
      let(:inbox) { channel.inbox }

      before { create(:inbox_member, user: author, inbox: inbox) }

      it 'fails with the reason and mentions the author in a private note' do
        travel_to(3.minutes.from_now) do
          described_class.new.perform(scheduled_message.id)

          expect(scheduled_message.reload.status).to eq('failed')
          expect(scheduled_message.failure_reason).to eq(I18n.t('whatsapp_send_block.disconnected'))
          note = conversation.messages.last
          expect(note.private).to be(true)
          expect(note.content).to include("mention://user/#{author.id}/")
          expect(conversation.messages.where(private: false, message_type: :outgoing)).to be_empty
        end
      end

      it 'moves a recurring series on to its next date' do
        recurring = create(:recurring_scheduled_message, conversation: conversation, author: author)
        scheduled_message.update!(recurring_scheduled_message: recurring)

        travel_to(3.minutes.from_now) do
          expect { described_class.new.perform(scheduled_message.id) }
            .to change { recurring.scheduled_messages.count }.by(1)
        end
      end
    end
  end
end
