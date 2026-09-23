require 'rails_helper'

RSpec.describe 'Funnel API', type: :request do
  let(:account) { create(:account, funnel_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  # Auto-assignment off keeps the seed lean — the pagination test builds
  # a few dozen conversations, which would otherwise fan out to Redis
  # round-robin work that has nothing to do with the funnel endpoint.
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }

  let!(:novo) { create(:funnel_stage, name: 'Novo Contato', position: 1) }
  let!(:qualificacao) { create(:funnel_stage, name: 'Em Qualificação', position: 2) }
  let!(:perdido) { create(:funnel_stage, name: 'Perdido', position: 3, requires_loss_reason: true, closed: true) }

  before { create(:inbox_member, user: admin, inbox: inbox) }

  describe 'GET /api/v1/accounts/:account_id/funnel' do
    it 'caps the number of cards per stage on first load and reports the total' do
      30.times { create(:conversation, account: account, inbox: inbox, funnel_stage: novo) }
      5.times { create(:conversation, account: account, inbox: inbox, funnel_stage: qualificacao) }

      get "/api/v1/accounts/#{account.id}/funnel?per_page=10",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      stages = response.parsed_body.dig('payload', 'stages')
      novo_stage = stages.find { |s| s['id'] == novo.id }
      qual_stage = stages.find { |s| s['id'] == qualificacao.id }

      expect(novo_stage['conversations'].size).to eq(10)
      expect(novo_stage['count']).to eq(30)
      expect(novo_stage['has_more']).to be true

      expect(qual_stage['conversations'].size).to eq(5)
      expect(qual_stage['count']).to eq(5)
      expect(qual_stage['has_more']).to be false
    end

    # The board rendered thousands of cards for accounts with a busy pipeline.
    # `label_list` (acts-as-taggable) and the loss-reason lookup used to fire
    # a query per card — this test locks in the batched shape so the render
    # runs a constant number of queries regardless of card count.
    it 'renders many cards without an N+1' do
      3.times { create(:conversation, account: account, inbox: inbox, funnel_stage: novo) }
      base = query_count do
        get "/api/v1/accounts/#{account.id}/funnel",
            headers: admin.create_new_auth_token,
            as: :json
      end

      12.times { create(:conversation, account: account, inbox: inbox, funnel_stage: novo) }
      grown = query_count do
        get "/api/v1/accounts/#{account.id}/funnel",
            headers: admin.create_new_auth_token,
            as: :json
      end

      # 12 extra cards must not cost 12 extra queries — allow a small slack
      # for the paginated fetch, but a per-card N+1 would be dozens more.
      expect(grown - base).to be < 5
    end

    it 'ships the batched loss_reason on a card that landed in a requires_loss_reason stage' do
      lost = create(:conversation, account: account, inbox: inbox, funnel_stage: perdido)
      loss_reason = create(:loss_reason, name: 'Sem interesse')
      create(:funnel_stage_change,
             account: account, conversation_id: lost.id, inbox: inbox, contact: lost.contact,
             previous_stage: 'Novo Contato', new_stage: 'Perdido', loss_reason: loss_reason,
             created_at: 1.hour.ago)

      get "/api/v1/accounts/#{account.id}/funnel",
          headers: admin.create_new_auth_token,
          as: :json

      perdido_payload = response.parsed_body.dig('payload', 'stages').find { |s| s['id'] == perdido.id }
      card = perdido_payload['conversations'].first
      expect(card['loss_reason']).to include('id' => loss_reason.id, 'name' => 'Sem interesse')
    end
  end

  describe 'GET /api/v1/accounts/:account_id/funnel/stages/:stage_id/conversations' do
    it 'brings the next page of a single column' do
      30.times { create(:conversation, account: account, inbox: inbox, funnel_stage: novo) }

      get "/api/v1/accounts/#{account.id}/funnel/stages/#{novo.id}/conversations?page=2&per_page=10",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body['payload']
      expect(body['stage_id']).to eq(novo.id)
      expect(body['conversations'].size).to eq(10)
      expect(body['meta']).to include('current_page' => 2, 'per_page' => 10, 'total' => 30, 'has_more' => true)
    end

    it 'reports the final page with has_more false' do
      12.times { create(:conversation, account: account, inbox: inbox, funnel_stage: novo) }

      get "/api/v1/accounts/#{account.id}/funnel/stages/#{novo.id}/conversations?page=2&per_page=10",
          headers: admin.create_new_auth_token,
          as: :json

      body = response.parsed_body['payload']
      expect(body['conversations'].size).to eq(2)
      expect(body['meta']).to include('has_more' => false, 'total' => 12)
    end
  end

  def query_count(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == 'SCHEMA' || payload[:sql] =~ /BEGIN|COMMIT|SAVEPOINT|RELEASE/ }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end
end
