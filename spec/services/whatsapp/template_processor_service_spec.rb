require 'rails_helper'

RSpec.describe Whatsapp::TemplateProcessorService do
  let(:channel) do
    create(:channel_whatsapp,
           provider: 'whatsapp_cloud',
           validate_provider_config: false,
           sync_templates: false,
           message_templates: templates_cache)
  end
  let(:message) { nil }

  describe 'header component with variables' do
    context 'when the template uses NAMED parameter_format' do
      # Real production bug: template with `{{nome}}` in the header was
      # being sent with a positional header parameter, and Meta rejected
      # with #132000 ("Number of parameters does not match the expected
      # number of params") even when the count was right — Meta requires
      # `parameter_name` on header params for NAMED templates.
      let(:templates_cache) do
        [
          {
            'name' => 'saudacao',
            'language' => 'pt_BR',
            'status' => 'approved',
            'parameter_format' => 'NAMED',
            'components' => [
              { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Olá {{nome}}' },
              { 'type' => 'BODY', 'text' => 'Corpo com {{cidade}}' }
            ]
          }
        ]
      end
      let(:template_params) do
        {
          'name' => 'saudacao',
          'language' => 'pt_BR',
          'processed_params' => {
            'header' => { 'nome' => 'Fabio' },
            'body' => { 'cidade' => 'Porto Alegre' }
          }
        }
      end

      it 'emits header parameters with parameter_name when parameter_format is NAMED' do
        _name, _namespace, _lang, components = described_class.new(
          channel: channel, template_params: template_params, message: message
        ).call

        header = components.find { |c| c[:type] == 'header' }
        expect(header[:parameters]).to eq([{ type: 'text', parameter_name: 'nome', text: 'Fabio' }])
      end
    end

    context 'when the template uses POSITIONAL parameter_format' do
      let(:templates_cache) do
        [
          {
            'name' => 'saudacao',
            'language' => 'pt_BR',
            'status' => 'approved',
            'parameter_format' => 'POSITIONAL',
            'components' => [
              { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Olá {{1}}' },
              { 'type' => 'BODY', 'text' => 'Corpo' }
            ]
          }
        ]
      end
      let(:template_params) do
        {
          'name' => 'saudacao',
          'language' => 'pt_BR',
          'processed_params' => {
            'header' => { '1' => 'Fabio' },
            'body' => {}
          }
        }
      end

      it 'keeps positional header parameters (no parameter_name)' do
        _name, _namespace, _lang, components = described_class.new(
          channel: channel, template_params: template_params, message: message
        ).call

        header = components.find { |c| c[:type] == 'header' }
        expect(header[:parameters]).to eq([{ type: 'text', text: 'Fabio' }])
      end
    end
  end

  # `example.header_handle` is Meta's preview URL and is not fetchable
  # from outside — passing it back to their send API returns 131053.
  # The sync flow resolves a reusable media_id via `/PHONE_NUMBER_ID/media`
  # and the processor prefers that id at send time.
  describe 'header component with a media header' do
    let(:templates_cache) do
      [
        {
          'name' => 'confirmacao',
          'language' => 'pt_BR',
          'status' => 'approved',
          'header_media_id' => 'CACHED_MEDIA_ID',
          'components' => [
            { 'type' => 'HEADER', 'format' => 'IMAGE',
              'example' => { 'header_handle' => ['https://scontent.whatsapp.net/preview.png'] } },
            { 'type' => 'BODY', 'text' => 'Olá {{1}}' }
          ]
        }
      ]
    end
    let(:template_params) do
      {
        'name' => 'confirmacao',
        'language' => 'pt_BR',
        'processed_params' => {
          'header' => { 'media_url' => 'https://scontent.whatsapp.net/preview.png', 'media_type' => 'image' },
          'body' => { '1' => 'Fabio' }
        }
      }
    end

    it 'sends the cached media_id, not the preview URL that would trigger 131053' do
      _name, _namespace, _lang, components = described_class.new(
        channel: channel, template_params: template_params, message: message
      ).call

      header = components.find { |c| c[:type] == 'header' }
      expect(header[:parameters]).to eq([{ type: 'image', image: { id: 'CACHED_MEDIA_ID' } }])
    end

    context 'when the template has no cached media_id yet' do
      let(:templates_cache) do
        [
          {
            'name' => 'confirmacao',
            'language' => 'pt_BR',
            'status' => 'approved',
            'components' => [
              { 'type' => 'HEADER', 'format' => 'IMAGE' },
              { 'type' => 'BODY', 'text' => 'Olá {{1}}' }
            ]
          }
        ]
      end

      # Degraded path: no cached id, so we still send the URL (which
      # is exactly the pre-fix behavior). Meta will 131053 and the
      # send flow's regenerate-on-131053 recovery takes over.
      it 'falls back to the URL when no media_id has been resolved' do
        _name, _namespace, _lang, components = described_class.new(
          channel: channel, template_params: template_params.deep_merge(
            'processed_params' => {
              'header' => { 'media_url' => 'https://example.com/logo.png', 'media_type' => 'image' }
            }
          ), message: message
        ).call

        header = components.find { |c| c[:type] == 'header' }
        expect(header[:parameters].first[:type]).to eq('image')
        expect(header[:parameters].first[:image][:link]).to include('example.com/logo.png')
      end
    end
  end
end
