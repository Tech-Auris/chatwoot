require 'rails_helper'

RSpec.describe Whatsapp::InstallFollowUpTemplatesJob do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:failure_labels) do
    ['auris_fup_geral', 'auris_fup_geral2', 'auris_fup_geral3', 'auris_fup_fim', 'auris_fup_fim (es)', 'auris_fup_fim (en)', 'auris_fup_fim (fr)']
  end
  let(:provider_service) { instance_double(Whatsapp::Providers::WhatsappCloudService, create_template: { success: true }) }

  before do
    allow(channel).to receive(:provider_service).and_return(provider_service)
    allow(channel).to receive(:sync_templates)
  end

  it 'creates the follow-up templates' do
    described_class.perform_now(channel)

    %w[auris_fup_geral auris_fup_geral2 auris_fup_geral3].each do |name|
      expect(provider_service).to have_received(:create_template).with(hash_including('name' => name, 'language' => 'pt_BR',
                                                                                      'category' => 'MARKETING', 'parameter_format' => 'NAMED'))
    end
  end

  it 'creates auris_fup_fim in every follow-up language' do
    described_class.perform_now(channel)

    { 'pt_BR' => 'Olá,', 'es' => 'Hola,', 'en' => 'Hello,', 'fr' => 'Bonjour,' }.each do |language, greeting|
      expect(provider_service).to have_received(:create_template).with(
        hash_including('name' => 'auris_fup_fim', 'language' => language, 'category' => 'UTILITY',
                       'components' => [hash_including('text' => start_with(greeting))])
      )
    end
  end

  it 'skips the templates the WABA already has' do
    channel.update_columns(message_templates: [{ 'name' => 'auris_fup_geral', 'language' => 'pt_BR', 'status' => 'APPROVED' }, # rubocop:disable Rails/SkipsModelValidations
                                               { 'name' => 'auris_fup_geral2', 'language' => 'en', 'status' => 'APPROVED' }])

    described_class.perform_now(channel)

    expect(provider_service).to have_received(:create_template).exactly(6).times
    expect(provider_service).not_to have_received(:create_template).with(hash_including('name' => 'auris_fup_geral'))
  end

  it 'only creates the languages the WABA is missing' do
    channel.update_columns(message_templates: [{ 'name' => 'auris_fup_fim', 'language' => 'pt_BR', 'status' => 'APPROVED' }]) # rubocop:disable Rails/SkipsModelValidations

    described_class.perform_now(channel)

    expect(provider_service).not_to have_received(:create_template).with(hash_including('name' => 'auris_fup_fim', 'language' => 'pt_BR'))
    expect(provider_service).to have_received(:create_template).with(hash_including('name' => 'auris_fup_fim', 'language' => 'es'))
  end

  it 'keeps going when Meta refuses one of them and returns the failures' do
    allow(provider_service).to receive(:create_template).and_return({ success: false, error_message: 'Invalid parameter' })

    failures = described_class.perform_now(channel)

    expect(provider_service).to have_received(:create_template).exactly(7).times
    expect(failures).to eq(failure_labels.index_with { 'Invalid parameter' })
  end

  it 'caches the created templates the sync does not return yet' do
    allow(provider_service).to receive(:create_template).and_return({ success: true, template: { 'id' => '77', 'status' => 'PENDING' } })

    described_class.perform_now(channel)

    cached = channel.reload.message_templates.index_by { |t| t['name'] }
    expect(cached['auris_fup_geral']).to include('id' => '77', 'status' => 'PENDING', 'language' => 'pt_BR')
  end

  it 'treats a template another number on the WABA already created as installed' do
    allow(provider_service).to receive(:create_template).and_return({ success: false, error_subcode: 2_388_024, error_message: 'already exists' })
    allow(Rails.logger).to receive(:warn)

    described_class.perform_now(channel)

    expect(Rails.logger).not_to have_received(:warn)
  end

  it 'shares the result with the other numbers on the same WABA' do
    sibling = create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)

    described_class.perform_now(channel)

    expect(Channels::Whatsapp::TemplatesCopyJob).to have_been_enqueued.with(sibling, channel)
  end

  it 'ignores channels that are not on the Cloud API' do
    channel.update_columns(provider: 'baileys') # rubocop:disable Rails/SkipsModelValidations

    described_class.perform_now(channel)

    expect(provider_service).not_to have_received(:create_template)
  end
end
