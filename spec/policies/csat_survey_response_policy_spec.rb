# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CsatSurveyResponsePolicy, type: :policy do
  subject(:csat_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:manager) { create(:user, account: account, role: :manager) }
  let(:agent) { create(:user, account: account) }
  let(:csat_survey_response) { create(:csat_survey_response, account: account) }

  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.first } }
  let(:manager_context) { { user: manager, account: account, account_user: manager.account_users.first } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.first } }

  permissions :index?, :metrics?, :download? do
    context 'when administrator' do
      it { expect(csat_policy).to permit(administrator_context, csat_survey_response) }
    end

    context 'when manager' do
      it { expect(csat_policy).to permit(manager_context, csat_survey_response) }
    end

    context 'when agent' do
      it { expect(csat_policy).not_to permit(agent_context, csat_survey_response) }
    end
  end
end
