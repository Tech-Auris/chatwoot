require 'rails_helper'

RSpec.describe Whatsapp::TemplateKit do
  describe '.meta_payload' do
    it 'builds a NAMED payload with the variable examples' do
      payload = described_class.meta_payload(described_class.find('lembrete_72h'))

      expect(payload).to include('name' => 'lembrete_72h', 'language' => 'pt_BR', 'category' => 'UTILITY', 'parameter_format' => 'NAMED')
      expect(payload['components'].first['example']['body_text_named_params']).to eq(
        [{ 'param_name' => 'nome', 'example' => 'Maria' }, { 'param_name' => 'dia', 'example' => '15/09/2026' },
         { 'param_name' => 'hora', 'example' => '14:30' }, { 'param_name' => 'profissional', 'example' => 'Dra. Ana Paula' }]
      )
    end

    it 'adds the quick replies' do
      buttons = described_class.meta_payload(described_class.find('lembrete_24h'))['components'].last

      quick_replies = %w[Confirmar Reagendar Cancelar].map { |text| { 'type' => 'QUICK_REPLY', 'text' => text } }
      expect(buttons).to eq('type' => 'BUTTONS', 'buttons' => quick_replies)
    end
  end

  it 'never starts or ends a body with a variable, which Meta rejects' do
    bodies = described_class.templates.map { |template| template['body'].strip }

    expect(bodies.select { |body| body.start_with?('{{') || body.end_with?('}}') }).to be_empty
  end

  describe '.violation' do
    let(:system_payload) { described_class.meta_payload(described_class.find('lembrete_24h')) }

    it 'refuses any write on a follow-up template' do
      expect(described_class.violation('auris_fup_geral')).to eq(I18n.t('errors.meta_templates.kit_reserved'))
      expect(described_class.violation('auris_fup_geral', { 'category' => 'MARKETING' })).to eq(I18n.t('errors.meta_templates.kit_reserved'))
    end

    it 'lets suggested, unknown and deleted system templates through' do
      expect(described_class.violation('boas_vindas', { 'category' => 'UTILITY', 'components' => [] })).to be_nil
      expect(described_class.violation('minha_promo', { 'category' => 'MARKETING' })).to be_nil
      expect(described_class.violation('lembrete_24h')).to be_nil
    end

    it 'accepts a system template with an edited body' do
      system_payload['components'].first['text'] = 'Oi {{nome}}, até {{dia}} às {{hora}}! Responda abaixo:'

      expect(described_class.violation('lembrete_24h', system_payload)).to be_nil
    end

    it 'refuses a system template with changed locked fields' do
      locked = I18n.t('errors.meta_templates.kit_locked_fields')
      expect(described_class.violation('lembrete_24h', system_payload.merge('category' => 'MARKETING'))).to eq(locked)
      expect(described_class.violation('lembrete_24h', system_payload.merge('language' => 'en'))).to eq(locked)

      system_payload['components'].last['buttons'].pop
      expect(described_class.violation('lembrete_24h', system_payload)).to eq(locked)
    end

    it 'refuses variables the engine does not fill' do
      system_payload['components'].first['text'] = 'Oi {{nome}}, seu convênio {{convenio}} vence {{1}}. Responda:'

      expect(described_class.violation('lembrete_24h', system_payload)).to include('convenio, 1')
    end
  end

  describe '.for_inbox' do
    let(:account) { create(:account, name: 'Clínica Sorriso') }
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
    end
    let(:inbox) { channel.inbox }

    before do
      channel.update_columns(message_templates: [{ 'id' => '9', 'name' => 'lembrete_72h', 'language' => 'pt_BR', 'status' => 'REJECTED' }]) # rubocop:disable Rails/SkipsModelValidations
    end

    it 'fills the clinic name and marks what the WABA already has' do
      kit = described_class.for_inbox(inbox).index_by { |template| template['name'] }

      expect(kit['lembrete_72h']).to include('group' => 'system', 'existing_id' => '9', 'existing_status' => 'REJECTED')
      expect(kit['lembrete_72h']['components'].first['text']).to include('na Clínica Sorriso no dia {{dia}}')
      expect(kit['lembrete_48h']['existing_status']).to be_nil
      expect(kit['confirmacao_agendamento']['components'].first['text']).to include('[endereço da clínica]')
    end

    it 'writes the business hours when the inbox has them' do
      inbox.update!(working_hours_enabled: true)
      inbox.working_hours.find_by(day_of_week: 6).update!(closed_all_day: false, open_hour: 8, open_minutes: 0, close_hour: 12, close_minutes: 30)

      text = described_class.for_inbox(inbox).find { |t| t['name'] == 'mensagem_fora_do_horario' }['components'].first['text']

      expect(text).to include('Nosso horário de atendimento é segunda a sexta, das 9h às 17h; sábado, das 8h às 12h30.')
    end

    it 'keeps the business hours placeholder while the inbox has none' do
      text = described_class.for_inbox(inbox).find { |t| t['name'] == 'mensagem_fora_do_horario' }['components'].first['text']

      expect(text).to include('[horário de funcionamento]')
    end
  end
end
