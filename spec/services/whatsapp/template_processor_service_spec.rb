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
end
