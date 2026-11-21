require 'rails_helper'

RSpec.describe VirtualClinic::Alerts::SeasonalPack do
  let(:account) { create(:account, virtual_clinic_enabled: true) }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

  around { |example| I18n.with_locale(:pt_BR) { example.run } }

  it 'tells the clinic once per season, at 9h, that the Christmas pack arrived' do
    rule = described_class.new(account, now: zone.local(2026, 11, 20, 9, 5))
    expect(rule.due?).to be(true)
    expect(rule.payload).to include(season: 'christmas', name: 'Natal', until: '31/12')

    account.virtual_clinic_alerts.create!(persona: :manager, rule: 'seasonal_pack', payload: rule.payload)
    expect(described_class.new(account, now: zone.local(2026, 11, 28, 9, 5)).payload).to be_nil
    # Next year, again.
    expect(described_class.new(account, now: zone.local(2027, 11, 16, 9, 5)).payload).to include(season: 'christmas')
  end

  it 'tells about Halloween too, but not about the party pack, which is always there' do
    expect(described_class.new(account, now: zone.local(2026, 10, 16, 9, 5)).payload).to include(season: 'halloween', until: '31/10')
    expect(described_class.new(account, now: zone.local(2026, 2, 10, 9, 5)).payload).to be_nil
  end

  it 'reads as Helena telling where to find it' do
    alert = account.virtual_clinic_alerts.create!(persona: :manager, rule: 'seasonal_pack',
                                                  payload: described_class.new(account, now: zone.local(2026, 11, 20, 9, 5)).payload)
    expect(alert.message).to start_with('Chegou o pacote de decoração de Natal! Até 31/12')
    expect(alert.message).to end_with('E o avatar ganhou um gorro natalino.')
  end
end
