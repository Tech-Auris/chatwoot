require 'rails_helper'

RSpec.describe 'Audiences API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/audiences" }
  let(:abc_rule) { [{ attribute_key: 'labels', filter_operator: 'equal_to', values: ['abc'], query_operator: nil }] }

  def contact_with_label(label, name: 'Maria')
    contact = create(:contact, account: account, name: name)
    create(:conversation, account: account, inbox: inbox, contact: contact).update_labels([label])
    contact
  end

  def body
    response.parsed_body['payload']
  end

  it 'refuses an unauthenticated request' do
    get base

    expect(response).to have_http_status(:unauthorized)
  end

  describe 'a dynamic audience' do
    it 'is created by an agent with its rule, and counted' do
      contact_with_label('abc')

      post base, params: { name: 'Reativação', kind: 'dynamic', rule: abc_rule, window: { type: 'last_days', days: 30 } },
                 headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(body).to include('name' => 'Reativação', 'kind' => 'dynamic', 'contacts_count' => 1)
      expect(Audience.last.created_by).to eq(agent)
    end

    it 'reports and drops the conditions it does not accept' do
      rule = [abc_rule.first.merge(query_operator: 'AND'),
              { attribute_key: 'browser_language', filter_operator: 'equal_to', values: ['en'], query_operator: nil }]

      post base, params: { name: 'Do filtro', kind: 'dynamic', source: 'filter', rule: rule },
                 headers: agent.create_new_auth_token, as: :json

      expect(body['ignored_conditions']).to eq(['browser_language'])
      expect(Audience.last.rule.pluck('attribute_key')).to eq(['labels'])
    end

    it 'keeps its rule when only the name changes' do
      audience = create(:audience, account: account, rule: abc_rule.map(&:stringify_keys))

      patch "#{base}/#{audience.id}", params: { name: 'Novo nome' }, headers: agent.create_new_auth_token, as: :json

      expect(audience.reload).to have_attributes(name: 'Novo nome', rule: abc_rule.map(&:stringify_keys))
    end

    it 'freezes into a static audience with its members right now' do
      contact = contact_with_label('abc')
      audience = create(:audience, account: account, rule: abc_rule.map(&:stringify_keys))

      post "#{base}/#{audience.id}/snapshot", params: { name: 'Foto de outubro' }, headers: agent.create_new_auth_token, as: :json

      frozen = Audience.find(body['id'])
      expect(frozen).to have_attributes(kind: 'static', source: 'snapshot', contacts_count: 1)
      expect(frozen.contacts).to contain_exactly(contact)
      expect(audience.events.last).to have_attributes(kind: 'snapshot', user_id: agent.id, contacts_count: 1)
    end

    it 'does not take contacts by hand' do
      audience = create(:audience, account: account)

      post "#{base}/#{audience.id}/add_contacts", params: { contact_ids: [create(:contact, account: account).id] },
                                                  headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'a static audience' do
    it 'stores the rule result at creation and then does not change by itself' do
      contact_with_label('abc')

      post base, params: { name: 'Fixo', kind: 'static', source: 'filter', rule: abc_rule }, headers: agent.create_new_auth_token, as: :json
      audience = Audience.find(body['id'])
      contact_with_label('abc', name: 'Depois')

      expect(audience.reload.contacts.count).to eq(1)
    end

    it 'takes and loses contacts by hand' do
      audience = create(:audience, account: account, kind: :static)
      first, second = create_list(:contact, 2, account: account)

      post "#{base}/#{audience.id}/add_contacts", params: { contact_ids: [first.id, second.id] }, headers: agent.create_new_auth_token, as: :json
      post "#{base}/#{audience.id}/remove_contacts", params: { contact_ids: [first.id] }, headers: agent.create_new_auth_token, as: :json

      expect(audience.reload.contacts).to contain_exactly(second)
      expect(body['contacts_count']).to eq(1)
    end

    it 'is created from a spreadsheet' do
      csv = Rack::Test::UploadedFile.new(StringIO.new("name,phone_number\nMaria,+5511987654321\n"), 'text/csv', original_filename: 'lista.csv')

      post "#{base}/import", params: { name: 'Lista importada', file: csv }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:created)
      expect(Audience.last).to have_attributes(kind: 'static', source: 'csv', contacts_count: 1)
    end
  end

  it 'tells the size of a rule while it is built' do
    contact_with_label('abc')

    post "#{base}/preview", params: { rule: abc_rule }, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('contacts_count' => 1, 'ignored_conditions' => [])
  end

  it 'lists the members page by page' do
    contact_with_label('abc', name: 'Maria')
    audience = create(:audience, account: account, rule: abc_rule.map(&:stringify_keys))

    get "#{base}/#{audience.id}/contacts", headers: agent.create_new_auth_token

    expect(body.pluck('name')).to eq(['Maria'])
    expect(body.first).to include('labels' => ['abc'], 'inbox_name' => inbox.name)
    expect(response.parsed_body['meta']['total_count']).to eq(1)
  end

  it 'lists the audiences of the account, filtered by kind' do
    create(:audience, account: account, name: 'Dinâmico')
    create(:audience, account: account, name: 'Fixo', kind: :static)
    create(:audience, account: create(:account), name: 'De outra conta')

    get base, params: { kind: 'static' }, headers: agent.create_new_auth_token

    expect(body.pluck('name')).to eq(['Fixo'])
    expect(response.parsed_body['meta']).to include('downloads_last_30_days' => 0, 'campaigns_last_30_days' => 0)
  end

  it 'shows what was done with an audience' do
    audience = create(:audience, account: account)
    audience.events.create!(kind: :download, user: agent, contacts_count: 12, format: 'csv')

    get "#{base}/#{audience.id}", headers: agent.create_new_auth_token

    expect(body['events'].first).to include('kind' => 'download', 'contacts_count' => 12, 'user_name' => agent.name)
  end

  it 'is deleted' do
    audience = create(:audience, account: account)

    delete "#{base}/#{audience.id}", headers: agent.create_new_auth_token

    expect(Audience.exists?(audience.id)).to be false
  end

  describe 'GET /audiences/:id/campaign_preview' do
    let(:administrator) { create(:user, account: account, role: :administrator) }
    let(:audience) { create(:audience, account: account, rule: abc_rule.map(&:stringify_keys)) }

    it 'tells who the campaign reaches and who stays out' do
      contact_with_label('abc').update!(phone_number: '+5511987654001')
      contact_with_label('abc', name: 'Sem telefone')
      opted_out = contact_with_label('abc', name: 'Opt-out')
      opted_out.update!(phone_number: '+5511987654002')
      opted_out.opt_out!(source: 'meta')

      get "#{base}/#{audience.id}/campaign_preview", headers: administrator.create_new_auth_token

      expect(response.parsed_body).to include('total_count' => 3, 'without_phone_count' => 1, 'opted_out_count' => 1,
                                              'already_received_count' => 0, 'will_receive_count' => 1, 'over_limit' => false)
    end

    it 'is only for administrators and managers' do
      get "#{base}/#{audience.id}/campaign_preview", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
