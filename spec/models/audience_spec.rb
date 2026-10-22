require 'rails_helper'

RSpec.describe Audience do
  it 'needs a valid window' do
    expect(build(:audience, window: { 'type' => 'last_days' })).not_to be_valid
    expect(build(:audience, window: { 'type' => 'range', 'from' => '2026-10-01' })).not_to be_valid
    expect(build(:audience, window: { 'type' => 'whenever' })).not_to be_valid
    expect(build(:audience, window: { 'type' => 'last_days', 'days' => 30 })).to be_valid
  end

  it 'adds a contact only once' do
    audience = create(:audience, kind: :static)
    contact = create(:contact, account: audience.account)

    2.times { audience.add_contacts([contact.id]) }

    expect(audience.contacts_count).to eq(1)
  end

  it 'never takes a contact from another account' do
    audience = create(:audience, kind: :static)

    audience.add_contacts([create(:contact).id])

    expect(audience.contacts).to be_empty
  end
end
