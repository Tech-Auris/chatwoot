require 'rails_helper'

RSpec.describe Sales::ReservationSyncService do
  let(:search_service) { instance_double(Sales::ClickupProspectSearchService) }
  let(:quote) { create(:sales_quote, status: :reserved, clickup_status: 'negociação', reserved_until: 3.days.from_now.change(usec: 0)) }

  def task(status: 'proposta enviada', due_date: nil)
    { task_id: quote.clickup_task_id, name: 'Clínica Exemplo', status: status, due_date: due_date }
  end

  it 'mirrors the status the deal has in clickup' do
    allow(search_service).to receive(:find).with(quote.clickup_task_id).and_return(task)

    described_class.new(quotes: [quote], search_service: search_service).perform

    expect(quote.reload.clickup_status).to eq('proposta enviada')
    expect(quote.clickup_status_synced_at).to be_present
  end

  it 'moves the deadline when it was changed in clickup' do
    new_deadline = 10.days.from_now.change(usec: 0)
    allow(search_service).to receive(:find).and_return(task(due_date: (new_deadline.to_f * 1000).to_i))

    described_class.new(quotes: [quote], search_service: search_service).perform

    expect(quote.reload.reserved_until).to be_within(1.second).of(new_deadline)
    expect(quote.events.pluck(:event)).to include('deadline_synced_from_clickup')
  end

  it 'keeps the deadline when clickup carries the same date' do
    allow(search_service).to receive(:find).and_return(task(due_date: (quote.reserved_until.to_f * 1000).to_i))

    described_class.new(quotes: [quote], search_service: search_service).perform

    expect(quote.events).to be_empty
  end

  # A report that cannot reach ClickUp is still worth rendering.
  it 'returns the quotes when clickup is unreachable' do
    allow(search_service).to receive(:find).and_raise(Sales::ClickupProspectSearchService::NotConfigured, 'sem lista')

    expect(described_class.new(quotes: [quote], search_service: search_service).perform).to eq([quote])
  end

  it 'skips a task that no longer exists in the pipeline' do
    allow(search_service).to receive(:find).and_return(nil)

    described_class.new(quotes: [quote], search_service: search_service).perform

    expect(quote.reload.clickup_status).to eq('negociação')
  end

  # Race: a seller renewed the reservation, which wrote to our DB and to
  # ClickUp. A concurrent page load then read the stale ClickUp prospect
  # cache (5-minute TTL) and would have overwritten the just-renewed
  # deadline back to the old one. `ReserveQuoteService` writes a marker
  # to the cache, and this service honours it — status still syncs, but
  # deadline stays as the fresh local write.
  it 'keeps a freshly-written deadline when the reserve marker is present' do
    freshly_written = quote.reserved_until
    stale_from_clickup = 3.days.ago.change(usec: 0)
    allow(search_service).to receive(:find).and_return(task(status: 'proposta enviada',
                                                            due_date: (stale_from_clickup.to_f * 1000).to_i))
    # Test env defaults to a null cache store, so stub the presence of the
    # marker directly for this specific key.
    marker_key = Sales::ReserveQuoteService.local_write_marker_key(quote.id)
    allow(Rails.cache).to receive(:exist?).and_call_original
    allow(Rails.cache).to receive(:exist?).with(marker_key).and_return(true)

    described_class.new(quotes: [quote], search_service: search_service).perform

    expect(quote.reload.reserved_until).to be_within(1.second).of(freshly_written)
    expect(quote.clickup_status).to eq('proposta enviada')
  end
end
