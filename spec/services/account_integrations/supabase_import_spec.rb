require 'rails_helper'

RSpec.describe AccountIntegrations::SupabaseImport do
  let(:dir) { Dir.mktmpdir }
  let(:account) { create(:account) }

  before do
    { 2 => 'Feegow', 7 => 'VisualASA CIG', 13 => 'Klingo', 15 => 'VisualASA Geral' }.each do |id, name|
      ErpSource.find_or_create_by!(id: id) { |erp| erp.name = name }
    end
  end

  after { FileUtils.remove_entry(dir) }

  def write_csv(table, header, *rows)
    File.write(File.join(dir, "integration_#{table}.csv"), ([header] + rows).join("\n"))
  end

  def import(apply: true)
    described_class.new(dir: dir, apply: apply).perform
  end

  it 'imports every column but cliente_id under the same names, parsing jsonb, and compares clean afterwards' do
    write_csv('feegow', 'cliente_id,access_token,local_id,unidade_id,procedimento_id,token_overrides',
              %(#{account.id},tok,10,,30,"{""5"": ""outro""}"))
    write_csv('klingo', 'cliente_id,app-token,link', "#{account.id},k-tok,https://klingo")

    results = import

    expect(account.account_integrations.find_by(erp_source_id: 2).config).to eq(
      'access_token' => 'tok', 'local_id' => '10', 'unidade_id' => nil, 'procedimento_id' => '30', 'token_overrides' => { '5' => 'outro' }
    )
    expect(account.account_integrations.find_by(erp_source_id: 13).config).to eq('app-token' => 'k-tok', 'link' => 'https://klingo')
    expect(results.map(&:differences)).to all(be_empty)
    expect(import(apply: false).map(&:differences)).to all(be_empty)
  end

  it 'is idempotent and replaces the config on rerun' do
    write_csv('klingo', 'cliente_id,app-token,link', "#{account.id},velho,l")
    import
    write_csv('klingo', 'cliente_id,app-token,link', "#{account.id},novo,l")

    expect { import }.not_to change(AccountIntegration, :count)
    expect(account.account_integrations.sole.config['app-token']).to eq('novo')
  end

  it 'maps the internal clientes 150 and 151 to accounts 19 and 66' do
    internal = Account.find_by(id: 19) || create(:account, id: 19)
    write_csv('klingo', 'cliente_id,app-token,link', '150,k,l')

    import

    expect(internal.account_integrations.sole.erp_source_id).to eq(13)
  end

  it "puts VisualASA under the account's VisualASA ERP, or CIG otherwise" do
    geral = create(:account, erp_source_id: 15)
    write_csv('visualasa', 'cliente_id,access_token,url,filial', "#{geral.id},a,u,1", "#{account.id},b,u,2")

    import

    expect(geral.account_integrations.sole.erp_source_id).to eq(15)
    expect(account.account_integrations.sole.erp_source_id).to eq(7)
  end

  it 'reports rows without an account and differences in the dry run without saving' do
    write_csv('klingo', 'cliente_id,app-token,link', '999999,k,l', "#{account.id},k,l")
    create(:account_integration, account: account, erp_source_id: 13, config: { 'app-token' => 'outro', 'link' => 'l' })

    results = import(apply: false)

    expect(results.map { |result| result.error || result.differences }).to eq(['conta não encontrada', ['app-token']])
    expect(account.account_integrations.sole.config['app-token']).to eq('outro')
  end
end
