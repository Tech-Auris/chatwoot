require 'rails_helper'

RSpec.describe AudiencePolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:audience) { create(:audience, account: account) }

  def context_for(role)
    user = create(:user, account: account, role: role)
    { user: user, account: account, account_user: account.account_users.find_by(user: user) }
  end

  permissions :index?, :show?, :create?, :update?, :destroy?, :snapshot?, :import? do
    it 'lets every account user build and browse audiences' do
      expect(policy).to permit(context_for(:agent), audience)
    end
  end

  permissions :export?, :use_in_campaign? do
    it 'keeps downloading and sending a campaign to administrators' do
      expect(policy).to permit(context_for(:administrator), audience)
    end

    it 'refuses them to agents' do
      expect(policy).not_to permit(context_for(:agent), audience)
    end
  end
end
