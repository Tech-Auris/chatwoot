require 'rails_helper'

RSpec.describe Whatsapp::TemplateRejectedClickupJob do
  let(:account) { create(:account, name: 'Clínica Sorriso') }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                              message_templates: [{ 'id' => '77', 'name' => 'auris_fup_geral2', 'language' => 'pt_BR', 'status' => 'REJECTED' }])
  end
  let(:comment_url) { %r{https://api.clickup.com/api/v2/task/(\w+)/comment} }

  before do
    stub_request(:post, comment_url).to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  around do |example|
    with_modified_env(FRONTEND_URL: 'https://chat.auris.ia.br') { example.run }
  end

  def configure(key, value)
    InstallationConfig.where(name: key).first_or_initialize.update!(value: value)
    GlobalConfig.clear_cache
  end

  context 'with the ClickUp key set' do
    before { configure('CLICKUP_API_KEY', 'pk_test') }

    it 'comments on the deal task of the converted proposal' do
      create(:sales_quote, account: account, status: :converted, clickup_task_id: 'deal123')

      described_class.perform_now(channel, '77', 'INVALID_FORMAT')

      expect(WebMock).to(have_requested(:post, 'https://api.clickup.com/api/v2/task/deal123/comment').with do |request|
        text = JSON.parse(request.body)['comment_text']
        text.include?('Template: auris_fup_geral2') && text.include?('Motivo: INVALID_FORMAT') &&
          text.include?("Conta: Clínica Sorriso (##{account.id})") &&
          text.include?("https://chat.auris.ia.br/app/accounts/#{account.id}/settings/meta-templates")
      end)
    end

    it 'falls back to the alert task when the account did not come from a sale' do
      create(:sales_quote, account: account, status: :draft, clickup_task_id: 'not_this')
      configure('CLICKUP_TEMPLATE_ALERT_TASK_ID', 'alerts1')

      described_class.perform_now(channel, '77', 'INVALID_FORMAT')

      expect(WebMock).to have_requested(:post, 'https://api.clickup.com/api/v2/task/alerts1/comment')
      expect(WebMock).not_to have_requested(:post, 'https://api.clickup.com/api/v2/task/not_this/comment')
    end

    it 'only logs when there is no task to comment on' do
      described_class.perform_now(channel, '77', 'INVALID_FORMAT')

      expect(WebMock).not_to have_requested(:post, comment_url)
    end
  end

  it 'only logs when ClickUp is not configured' do
    configure('CLICKUP_TEMPLATE_ALERT_TASK_ID', 'alerts1')

    described_class.perform_now(channel, '77', 'INVALID_FORMAT')

    expect(WebMock).not_to have_requested(:post, comment_url)
  end
end
