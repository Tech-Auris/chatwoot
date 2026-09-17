require 'rails_helper'

RSpec.describe V2::Reports::OrigemSummaryBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:params) { { since: 7.days.ago.to_time.to_i.to_s, until: Time.zone.now.end_of_day.to_time.to_i.to_s } }
  let(:builder) { described_class.new(account: account, params: params) }

  def conversation_with_origem(origem, created_at: 1.day.ago)
    create(:conversation, account: account, inbox: inbox, origem: origem, created_at: created_at)
  end

  describe '#build' do
    it 'returns one row per fixed origem + a Sem origem bucket, in a stable order' do
      report = builder.build

      names = report.map { |row| row[:name] }
      expect(names).to eq(V2::Reports::OrigemSummaryBuilder::OPTIONS + ['Sem origem'])
    end

    it 'counts conversations per origem in the period' do
      2.times { conversation_with_origem('Facebook') }
      conversation_with_origem('Instagram')

      report = builder.build

      expect(report.find { |r| r[:name] == 'Facebook' }[:conversations_count]).to eq(2)
      expect(report.find { |r| r[:name] == 'Instagram' }[:conversations_count]).to eq(1)
      expect(report.find { |r| r[:name] == 'Google' }[:conversations_count]).to eq(0)
    end

    # Conversations without an origem (nil column) fall into the "Sem origem"
    # bucket — the operator sees unattributed leads without them silently
    # disappearing from totals. Empty strings are impossible today (validation
    # only allows OPTIONS or nil), but a legacy row would still collapse.
    it 'collapses conversations without an origem into the Sem origem row' do
      conversation_with_origem(nil)
      conversation_with_origem(nil)

      report = builder.build

      expect(report.find { |r| r[:name] == 'Sem origem' }).to include(
        id: V2::Reports::OrigemSummaryBuilder::NONE_TOKEN,
        conversations_count: 2
      )
    end

    it 'ignores conversations outside the period' do
      conversation_with_origem('Google', created_at: 60.days.ago)

      expect(builder.build.find { |r| r[:name] == 'Google' }[:conversations_count]).to eq(0)
    end
  end
end
