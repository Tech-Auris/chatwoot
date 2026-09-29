require 'rails_helper'

RSpec.describe Sales::ReservationReminderJob do
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:messenger) { instance_double(Sales::LeadWhatsappMessenger) }
  let(:conversation) { create(:conversation) }

  def quote_ending_today(**attrs)
    create(:sales_quote, status: :reserved, reserved_until: zone.now.end_of_day, **attrs)
  end

  before do
    allow(Sales::LeadWhatsappMessenger).to receive(:new).and_return(messenger)
    allow(messenger).to receive(:perform).and_return(conversation)
  end

  it 'waits for the configured time of the last day' do
    quote_ending_today
    travel_to(zone.now.change(hour: 12, min: 0)) { described_class.perform_now }

    expect(Sales::LeadWhatsappMessenger).not_to have_received(:new)
  end

  it 'reminds the open reservations ending today, once' do
    due = quote_ending_today(meeting_discount: true, meeting_discount_amount: 139_500)
    quote_ending_today(status: :paid)
    create(:sales_quote, status: :reserved, reserved_until: zone.now.end_of_day + 1.day)

    travel_to(zone.now.change(hour: 12, min: 40)) do
      described_class.perform_now
      described_class.perform_now
    end

    expect(Sales::LeadWhatsappMessenger).to have_received(:new).once
    expect(Sales::LeadWhatsappMessenger).to have_received(:new).with(quote: due, content: include('R$ 1.395,00'))
    expect(due.events.where(event: 'whatsapp_last_day_reminder_sent').count).to eq(1)
  end

  it 'honours the reminder time set in Settings → Commercial' do
    quote_ending_today
    InstallationConfig.where(name: 'COMMERCIAL_RESERVATION_REMINDER_TIME').first_or_create!(value: '09:00', locked: false).update!(value: '09:00')
    GlobalConfig.clear_cache

    travel_to(zone.now.change(hour: 9, min: 5)) { described_class.perform_now }

    expect(Sales::LeadWhatsappMessenger).to have_received(:new).once
  end
end
