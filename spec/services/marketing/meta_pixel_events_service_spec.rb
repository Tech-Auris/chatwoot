require 'rails_helper'

RSpec.describe Marketing::MetaPixelEventsService do
  let(:account) { create(:account) }
  let(:integration) do
    create(:marketing_integration,
           account: account, provider: :meta_capi, status: :active,
           credentials: { 'pixel_id' => '999', 'access_token' => 'EAAG_test' })
  end

  def stub_stats(payload, code: 200)
    stub_request(:get, %r{graph\.facebook\.com/v20\.0/999/stats})
      .to_return(status: code, body: payload.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe '#perform' do
    # Standard Events are the fixed catalog Meta ships for CAPI. Every
    # operator sees them even when the pixel has not received any traffic
    # yet — the combobox is not empty out of the box.
    it 'ships the standard-event catalog on the response' do
      stub_stats({ data: [] })

      result = described_class.new(integration: integration).perform

      expect(result[:standard]).to include('Lead', 'Purchase', 'Schedule')
    end

    it 'reports custom event names the pixel received in the last 30 days' do
      stub_stats({ data: [{ 'data' => { 'AgendarConsulta' => 12, 'FormularioInterno' => 3 } }] })

      result = described_class.new(integration: integration).perform

      expect(result[:custom]).to contain_exactly('AgendarConsulta', 'FormularioInterno')
    end

    # A Standard Event that the pixel *has* seen already lives on the
    # `standard` list — no need to repeat it under `custom`.
    it 'drops names already in the standard catalog from the custom list' do
      stub_stats({ data: [{ 'data' => { 'Lead' => 40, 'AgendarConsulta' => 4 } }] })

      result = described_class.new(integration: integration).perform

      expect(result[:custom]).to contain_exactly('AgendarConsulta')
    end

    # A broken Meta call (revoked token, network hiccup) must not lock
    # the operator out of the form — the standard catalog still comes
    # through and the datalist just has no custom entries.
    it 'falls back to an empty custom list when Meta answers with an error' do
      stub_stats({ error: { message: 'Invalid access token' } }, code: 400)

      result = described_class.new(integration: integration).perform

      expect(result[:custom]).to eq([])
      expect(result[:standard]).to include('Lead')
    end

    # A disabled integration whose credentials were cleared (rare, but
    # possible after a Meta reset) — the fetcher must not blow up nor
    # hit Graph with an empty pixel id.
    it 'skips the fetch entirely when credentials are missing' do
      # `disabled` bypasses the `required_credentials_present` guard on
      # the model, so we can force blank keys through the DB.
      integration.update!(status: :disabled)
      # `disabled` also skips the credentials validation, so we can blank
      # them out through the model's own setter without hitting the guard.
      integration.credentials = { 'pixel_id' => '', 'access_token' => '' }
      integration.save!(validate: false)

      result = described_class.new(integration: integration.reload).perform

      expect(result[:custom]).to eq([])
      expect(WebMock).not_to have_requested(:get, /graph\.facebook\.com/)
    end

    # A Google Ads integration was passed by mistake — the fetcher only
    # applies to Meta CAPI, so bail early instead of hitting Graph with a
    # meaningless pixel_id.
    it 'skips the fetch when the integration is not meta_capi' do
      google = create(:marketing_integration, :google_ads, account: account)

      result = described_class.new(integration: google).perform

      expect(result[:custom]).to eq([])
      expect(WebMock).not_to have_requested(:get, /graph\.facebook\.com/)
    end
  end
end
