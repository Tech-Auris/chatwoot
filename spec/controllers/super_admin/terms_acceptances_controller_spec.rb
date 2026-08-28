require 'rails_helper'

RSpec.describe 'Super Admin Terms Acceptances', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:terms_version) { create(:terms_version, content: '<h1>Termos</h1><p>Conteúdo assinado</p>') }

  let!(:signed) do
    create(:terms_acceptance, terms_version: terms_version, status: :signed, signer_name: 'Felicia Macedo',
                              signer_email: 'felicia@exemplo.com', signed_at: 1.day.ago, ip_address: '187.1.1.1',
                              user_agent: 'Mozilla/5.0 (Macintosh)')
  end
  # A pending request sits next to the signed one so the status filter has
  # something to leave out.
  let!(:pending_request) { create(:terms_acceptance, terms_version: terms_version, status: :pending) }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'renders the screen' do
    get '/super_admin/terms_acceptances'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('TermsAcceptancesIndex')
  end

  it 'lists the acceptances with who signed and from where' do
    get '/super_admin/terms_acceptances/data'

    row = response.parsed_body['acceptances'].find { |item| item['id'] == signed.id }
    expect(row).to include('signer_name' => 'Felicia Macedo', 'ip_address' => '187.1.1.1',
                           'user_agent' => 'Mozilla/5.0 (Macintosh)')
    expect(row['signed_at']).to be_present
  end

  it 'filters by status' do
    get '/super_admin/terms_acceptances/data'

    expect(response.parsed_body['acceptances'].pluck('id')).to contain_exactly(signed.id, pending_request.id)

    get '/super_admin/terms_acceptances/data', params: { status: 'signed' }

    expect(response.parsed_body['acceptances'].pluck('id')).to eq([signed.id])
  end

  # The audit is only worth anything if it shows the exact text that was
  # accepted, not whatever the site says today.
  it 'returns the frozen text that was signed' do
    get "/super_admin/terms_acceptances/#{signed.id}"

    expect(response.parsed_body['content']).to include('Conteúdo assinado')
    expect(response.parsed_body['acceptance']['content_hash']).to eq(terms_version.content_hash)
  end

  it 'refuses an anonymous visitor' do
    sign_out(:super_admin)

    get '/super_admin/terms_acceptances/data'

    expect(response).to have_http_status(:redirect)
  end
end
