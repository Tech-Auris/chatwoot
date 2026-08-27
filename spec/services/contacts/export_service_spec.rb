require 'rails_helper'

RSpec.describe Contacts::ExportService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }

  def export(column_names: nil, params: {})
    described_class.new(account: account, user: user, column_names: column_names, params: params).perform
  end

  # The file starts with a BOM for spreadsheets; parsing keeps it glued to the
  # first header unless it is stripped here.
  def export_rows(**)
    CSV.parse(export(**).delete_prefix(described_class::BOM), headers: true)
  end

  it 'exports the default columns' do
    create(:contact, account: account, name: 'Maria Souza', email: 'maria@exemplo.com')

    rows = export_rows

    expect(rows.headers).to eq(%w[id name email phone_number labels])
    expect(rows.first['name']).to eq('Maria Souza')
  end

  it 'keeps the order of the requested columns' do
    create(:contact, account: account, phone_number: '+5511900000006')

    rows = export_rows(column_names: %w[phone_number name])

    expect(rows.headers).to eq(%w[phone_number name])
  end

  it 'ignores a column that does not exist on the contact' do
    create(:contact, account: account, phone_number: '+5511900000007')

    rows = export_rows(column_names: %w[name inventado])

    expect(rows.headers).to eq(['name'])
  end

  it 'joins the labels of each contact' do
    create(:label, account: account, title: 'vip')
    create(:label, account: account, title: 'suporte')
    create(:contact, account: account, name: 'Com etiquetas', phone_number: '+5511900000001').add_labels(%w[vip suporte])

    rows = export_rows

    expect(rows.first['labels'].split(',')).to match_array(%w[vip suporte])
  end

  # A tag that is not a declared label of the account must not leak into a file
  # the operator hands to somebody else.
  it 'leaves out tags that are not labels of the account' do
    create(:label, account: account, title: 'vip')
    create(:contact, account: account, phone_number: '+5511900000002').add_labels(%w[vip tag_solta])

    rows = export_rows

    expect(rows.first['labels']).to eq('vip')
  end

  it 'exports only the contacts carrying the filtered label' do
    create(:label, account: account, title: 'vip')
    create(:contact, account: account, name: 'Com vip', phone_number: '+5511900000003').add_labels(['vip'])
    create(:contact, account: account, name: 'Sem vip', phone_number: '+5511900000004')

    rows = export_rows(params: { label: 'vip' })

    expect(rows.pluck('name')).to eq(['Com vip'])
  end

  # The file is built inside a web request now, so an account with many
  # contacts must not be loaded into memory in one go.
  it 'reads the contacts in batches' do
    stub_const('Contacts::ExportService::BATCH_SIZE', 2)
    5.times { |index| create(:contact, account: account, name: "Contato #{index}", phone_number: "+551190000001#{index}") }

    rows = export_rows

    expect(rows.length).to eq(5)
  end

  it 'prepends the BOM spreadsheets need to read accents' do
    create(:contact, account: account, name: 'João', phone_number: '+5511900000005')

    expect(export.b).to start_with("\xEF\xBB\xBF".b)
  end

  it 'names the file after the account' do
    service = described_class.new(account: account, user: user, column_names: nil, params: {})

    expect(service.filename).to eq("#{account.name}_#{account.id}_contacts.csv")
  end
end
