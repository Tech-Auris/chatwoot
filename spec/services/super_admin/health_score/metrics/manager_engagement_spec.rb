require 'rails_helper'

RSpec.describe SuperAdmin::HealthScore::Metrics::ManagerEngagement do
  let(:on) { Date.current }
  let(:account) { create(:account) }

  it 'returns missing when the account has no manager role' do
    create(:user, account: account, role: :agent)

    result = described_class.new(account, on: on).compute

    expect(result).to include(missing: true, reason: 'no_manager_role')
  end

  it 'returns 100 when any manager was active in the dashboard in the last 7 days' do
    manager = create(:user, account: account, role: :agent)
    AccountUser.find_by(user: manager, account: account).update!(role: :manager)
    UserSession.create!(user: manager, client_id: 'c1', last_activity_at: 2.days.ago)

    result = described_class.new(account, on: on).compute

    expect(result[:sub_score]).to eq(100)
    expect(result.dig(:raw, :recent_login)).to be true
  end

  it 'returns 0 when the manager has no recent activity' do
    manager = create(:user, account: account, role: :agent)
    AccountUser.find_by(user: manager, account: account).update!(role: :manager)
    UserSession.create!(user: manager, client_id: 'c2', last_activity_at: 30.days.ago)

    result = described_class.new(account, on: on).compute

    expect(result[:sub_score]).to eq(0)
    expect(result.dig(:raw, :recent_login)).to be false
  end

  it 'returns 0 when the manager has no session tracked at all' do
    manager = create(:user, account: account, role: :agent)
    AccountUser.find_by(user: manager, account: account).update!(role: :manager)

    result = described_class.new(account, on: on).compute

    expect(result[:sub_score]).to eq(0)
    expect(result.dig(:raw, :last_activity_at)).to be_nil
  end
end
