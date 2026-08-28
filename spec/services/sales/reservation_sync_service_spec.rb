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
end
