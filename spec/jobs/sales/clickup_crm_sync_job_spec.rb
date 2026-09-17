require 'rails_helper'

RSpec.describe Sales::ClickupCrmSyncJob do
  let(:quote) { create(:sales_quote) }
  let(:service) { instance_double(Sales::ClickupCrmSyncService) }

  before { allow(Sales::ClickupCrmSyncService).to receive(:new).and_return(service) }

  it 'runs the paid-fields sync when the phase is paid_fields' do
    allow(service).to receive(:sync_paid_fields!)

    described_class.perform_now(quote.id, 'paid_fields')

    expect(service).to have_received(:sync_paid_fields!)
  end

  it 'flips the pipeline status when the phase is closed' do
    allow(service).to receive(:mark_closed!)

    described_class.perform_now(quote.id, 'closed')

    expect(service).to have_received(:mark_closed!)
  end

  # Sidekiq can retry after the quote is destroyed (rare but possible), and a
  # missing quote should not raise the job into the dead set.
  it 'is a no-op when the quote is gone' do
    described_class.perform_now(quote.id + 999, 'paid_fields')

    expect(Sales::ClickupCrmSyncService).not_to have_received(:new)
  end

  # An unexpected phase name should not blow up — Sidekiq's dead set gains
  # nothing by keeping a job we cannot re-run into a valid state.
  it 'does not blow up when the phase is unknown' do
    expect { described_class.perform_now(quote.id, 'nope') }.not_to raise_error
  end
end
