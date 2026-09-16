require 'rails_helper'

RSpec.describe V2::Reports::OrigemSummaryBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:params) { { since: 7.days.ago.to_time.to_i.to_s, until: Time.zone.now.end_of_day.to_time.to_i.to_s } }
  let(:builder) { described_class.new(account: account, params: params) }

  def contact_with_origem(origem)
    attrs = origem.nil? ? {} : { 'origem' => origem }
    create(:contact, account: account, additional_attributes: attrs)
  end

  def conversation_for(contact, created_at: 1.day.ago)
    create(:conversation, account: account, inbox: inbox, contact: contact, created_at: created_at)
  end

  describe '#build' do
    it 'returns one row per fixed origem + a Sem origem bucket, in a stable order' do
      report = builder.build

      names = report.map { |row| row[:name] }
      expect(names).to eq(V2::Reports::OrigemSummaryBuilder::OPTIONS + ['Sem origem'])
    end

    it 'counts conversations per contact origem in the period' do
      facebook_contact = contact_with_origem('Facebook')
      instagram_contact = contact_with_origem('Instagram')
      2.times { conversation_for(facebook_contact) }
      conversation_for(instagram_contact)

      report = builder.build

      expect(report.find { |r| r[:name] == 'Facebook' }[:conversations_count]).to eq(2)
      expect(report.find { |r| r[:name] == 'Instagram' }[:conversations_count]).to eq(1)
      expect(report.find { |r| r[:name] == 'Google' }[:conversations_count]).to eq(0)
    end

    # Contacts with an explicit blank string and contacts with no `origem` key
    # both fall into the same "Sem origem" bucket — the operator sees
    # unattributed leads without them silently disappearing from totals.
    it 'collapses contacts without an origem into the Sem origem row' do
      no_attr_contact = contact_with_origem(nil)
      blank_contact = create(:contact, account: account, additional_attributes: { 'origem' => '' })
      conversation_for(no_attr_contact)
      conversation_for(blank_contact)

      report = builder.build

      expect(report.find { |r| r[:name] == 'Sem origem' }).to include(
        id: V2::Reports::OrigemSummaryBuilder::NONE_TOKEN,
        conversations_count: 2
      )
    end

    it 'ignores conversations outside the period' do
      contact = contact_with_origem('Google')
      conversation_for(contact, created_at: 60.days.ago)

      expect(builder.build.find { |r| r[:name] == 'Google' }[:conversations_count]).to eq(0)
    end
  end
end
