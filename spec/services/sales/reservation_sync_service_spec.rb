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

  # ClickUp stores the deadline as an epoch of São Paulo midnight for the
  # picked day. Locally we keep "reserved through the whole day", so the
  # value that lands on `reserved_until` is the São Paulo end-of-day of
  # the same date the epoch points at.
  it 'moves the deadline when it was changed in clickup' do
    new_deadline_epoch_ms = 10.days.from_now.in_time_zone('America/Sao_Paulo').beginning_of_day.to_i * 1000
    allow(search_service).to receive(:find).and_return(task(due_date: new_deadline_epoch_ms))

    described_class.new(quotes: [quote], search_service: search_service).perform

    expected = Time.zone.at(new_deadline_epoch_ms / 1000).in_time_zone('America/Sao_Paulo').end_of_day
    expect(quote.reload.reserved_until).to be_within(1.second).of(expected)
    expect(quote.events.pluck(:event)).to include('deadline_synced_from_clickup')
  end

  it 'keeps the deadline when clickup carries the same day (even at a different time)' do
    # Local deadline sits at UTC end-of-day for the picked date; ClickUp
    # carries São Paulo midnight of the same date. Different absolute Time,
    # same São Paulo calendar day — the sync must leave the row alone.
    picked_day = quote.reserved_until.in_time_zone('America/Sao_Paulo').to_date
    clickup_epoch_ms = picked_day.in_time_zone('America/Sao_Paulo').to_i * 1000
    allow(search_service).to receive(:find).and_return(task(due_date: clickup_epoch_ms))

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
