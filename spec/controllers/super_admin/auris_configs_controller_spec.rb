require 'rails_helper'

RSpec.describe 'Super Admin n8n configs', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let!(:folder) { create(:auris_config, config_key: 'GDrive.RootFolderId', default_value: '1') }
  let!(:bounce) { create(:auris_config, config_key: 'Secretaria.BounceSeconds', default_value: '40') }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'edits a default value' do
    patch "/super_admin/auris_configs/#{bounce.id}", params: { auris_config: { default_value: '30' } }

    expect(bounce.reload.default_value).to eq('30')
  end

  it "shows the account's own values and the defaults on the account page" do
    create(:account_auris_config, account: account, auris_config: folder, value: 'pasta-da-clinica')

    get "/super_admin/accounts/#{account.id}"

    expect(response.body).to include('pasta-da-clinica', '40 (padrão)')
    expect(Nokogiri::HTML(response.body).css('a').pluck('href'))
      .to include(new_super_admin_account_auris_config_path(account_id: account.id, auris_config_id: bounce.id))
  end

  it 'opens the new value form on the account and key it came from' do
    get '/super_admin/account_auris_configs/new', params: { account_id: account.id, auris_config_id: bounce.id }

    page = Nokogiri::HTML(response.body)
    expect(page.at_css('select#account_auris_config_auris_config_id option[selected]')['value']).to eq(bounce.id.to_s)
  end

  it 'sets a value for the account and goes back to the account' do
    post '/super_admin/account_auris_configs', params: {
      account_auris_config: { account_id: account.id, auris_config_id: folder.id, value: 'nova-pasta' }
    }

    expect(account.account_auris_configs.find_by(auris_config: folder).value).to eq('nova-pasta')
    expect(response).to redirect_to(super_admin_account_path(account))
  end
end
