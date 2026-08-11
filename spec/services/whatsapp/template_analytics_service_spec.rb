require 'rails_helper'

RSpec.describe Whatsapp::TemplateAnalyticsService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp,
           account: account,
           provider: 'whatsapp_cloud',
           validate_provider_config: false,
           sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:template_name) { 'confirmacao_agenda' }
  let(:template_language) { 'pt_BR' }

  # Helper: create outgoing messages, some with template_params, in an
  # arbitrary status. Everything the service reads (source_id, status,
  # additional_attributes, message_type, inbox_id) is set here so each
  # example expresses one situation cleanly.
  def create_template_message(status:, source_id: nil, template_name_override: nil, language_override: nil, created_at: 1.day.ago)
    create(:message,
           inbox: inbox,
           account: account,
           conversation: conversation,
           message_type: :outgoing,
           status: status,
           source_id: source_id,
           created_at: created_at,
           additional_attributes: {
             'template_params' => {
               'name' => template_name_override || template_name,
               'language' => language_override || template_language
             }
           })
  end

  describe '#call' do
    it 'returns a full funnel breakdown over the requested window' do
      # 5 attempts total in the 30d window:
      # 3 accepted (source_id set) → 1 read, 1 delivered, 1 failed after accept
      # 2 rejected by Meta at request time (source_id nil, status failed)
      create_template_message(status: :read, source_id: 'wamid.1')
      create_template_message(status: :delivered, source_id: 'wamid.2')
      create_template_message(status: :failed, source_id: 'wamid.3')
      create_template_message(status: :failed, source_id: nil)
      create_template_message(status: :failed, source_id: nil)

      result = described_class.new(
        inbox: inbox, template_name: template_name, template_language: template_language, period: '30d'
      ).call

      expect(result[:period]).to eq('30d')
      expect(result[:period_days]).to eq(30)
      expect(result[:funnel]).to include(
        sent: 5,
        accepted_by_meta: 3,
        failed_sync: 2,
        delivered: 2,
        read: 1,
        failed_after_accept: 1
      )
    end

    it 'is case-insensitive on the template language' do
      # Users can save the template as pt_BR in Meta but the send-time
      # payload sometimes lowercases it depending on the caller. The
      # analytics query normalises both sides so counts stay consistent.
      create_template_message(status: :delivered, source_id: 'wamid.a', language_override: 'PT_BR')
      create_template_message(status: :read, source_id: 'wamid.b', language_override: 'pt_br')

      result = described_class.new(
        inbox: inbox, template_name: template_name, template_language: 'pt_BR', period: '30d'
      ).call

      expect(result[:funnel][:sent]).to eq(2)
    end

    it 'ignores messages outside the requested window' do
      # 45 days ago is inside 90d but outside 30d — the 30d call must
      # skip it, the 90d call must include it.
      create_template_message(status: :delivered, source_id: 'wamid.old', created_at: 45.days.ago)
      create_template_message(status: :delivered, source_id: 'wamid.recent', created_at: 3.days.ago)

      thirty = described_class.new(
        inbox: inbox, template_name: template_name, template_language: template_language, period: '30d'
      ).call
      ninety = described_class.new(
        inbox: inbox, template_name: template_name, template_language: template_language, period: '90d'
      ).call

      expect(thirty[:funnel][:sent]).to eq(1)
      expect(ninety[:funnel][:sent]).to eq(2)
    end

    it 'does not leak messages of other templates or other inboxes' do
      other_inbox = create(:inbox, account: account)
      # Same account, other inbox — must not count
      create(:message,
             inbox: other_inbox, account: account,
             conversation: create(:conversation, inbox: other_inbox, account: account),
             message_type: :outgoing, status: :read, source_id: 'wamid.other',
             additional_attributes: { 'template_params' => { 'name' => template_name, 'language' => template_language } })
      # Same inbox, other template
      create_template_message(status: :read, source_id: 'wamid.a', template_name_override: 'lembrete')
      # Match
      create_template_message(status: :read, source_id: 'wamid.match')

      result = described_class.new(
        inbox: inbox, template_name: template_name, template_language: template_language, period: '30d'
      ).call

      expect(result[:funnel][:sent]).to eq(1)
    end

    it 'falls back to 30d when the period value is not one of the allowed keys' do
      result = described_class.new(
        inbox: inbox, template_name: template_name, template_language: template_language, period: 'lifetime'
      ).call

      expect(result[:period]).to eq('30d')
    end

    it 'returns a zeroed funnel when no messages match' do
      result = described_class.new(
        inbox: inbox, template_name: template_name, template_language: template_language, period: '7d'
      ).call

      expect(result[:funnel]).to include(sent: 0, accepted_by_meta: 0, failed_sync: 0, delivered: 0, read: 0, failed_after_accept: 0)
    end
  end
end
