require 'rails_helper'
require Rails.root.join('db/migrate/20261116180000_cap_user_tokens_expiry.rb')

# Sessions opened before the 7-day lifespan follow it from the deploy on.
RSpec.describe CapUserTokensExpiry do
  let(:user) { create(:user) }

  before do
    user.update!(tokens: {
                   'old' => { 'token' => 'x', 'expiry' => 2.months.from_now.to_i },
                   'recent' => { 'token' => 'y', 'expiry' => 2.days.from_now.to_i }
                 })
    migration = described_class.new
    migration.verbose = false
    migration.up
  end

  it 'caps longer tokens at 7 days from now' do
    expect(user.reload.tokens['old']['expiry']).to be_within(5).of(7.days.from_now.to_i)
  end

  it 'keeps tokens that already expire sooner' do
    expect(user.reload.tokens['recent']['expiry']).to be_within(5).of(2.days.from_now.to_i)
  end
end
