require 'rails_helper'

RSpec.describe Sales::ReserveQuoteService do
  let(:client) { instance_double(Integrations::Clickup::Client, configured?: true) }
  let(:user) { create(:user) }
  let(:quote) { create(:sales_quote, clickup_task_id: '86ak7rd8j') }
  let(:deadline) { 5.days.from_now.change(usec: 0) }

  def reserve(quote_record = quote, until_date = deadline)
    described_class.new(quote: quote_record, reserved_until: until_date, user: user, client: client).perform
  end

  before do
    allow(client).to receive(:update_task)
    allow(client).to receive(:add_tag)
  end

  it 'holds the proposal until the date' do
    result = reserve

    expect(result.quote.reload).to have_attributes(status: 'reserved', reserved_until: deadline)
  end

  # ClickUp takes epoch milliseconds; sending seconds would date the task to 1970.
  it 'mirrors the deadline onto the ClickUp task in milliseconds' do
    reserve

    expect(client).to have_received(:update_task)
      .with('86ak7rd8j', hash_including(due_date: deadline.to_i * 1000))
  end

  it 'tags the task so the pipeline shows it is reserved' do
    reserve

    expect(client).to have_received(:add_tag).with('86ak7rd8j', 'reserva')
  end

  # A hiccup at ClickUp must not block a sale happening in front of a customer,
  # but nobody can be left believing the task was updated either.
  it 'still reserves when ClickUp refuses, and says so' do
    allow(client).to receive(:update_task).and_raise(Integrations::Clickup::Client::ProviderUnavailable, 'ClickUp 500')

    result = reserve

    expect(result.quote.reload.status).to eq('reserved')
    expect(result).to have_attributes(clickup_synced: false, clickup_error: 'ClickUp 500')
    expect(quote.events.last.metadata).to include('clickup_error' => 'ClickUp 500')
  end

  it 'reserves without ClickUp configured at all' do
    allow(client).to receive(:configured?).and_return(false)

    expect(reserve.clickup_synced).to be false
    expect(quote.reload.status).to eq('reserved')
  end

  describe 'renewal' do
    it 'writes the new deadline to the task, keeping it a mirror' do
      reserve
      new_deadline = 12.days.from_now.change(usec: 0)

      reserve(quote, new_deadline)

      expect(quote.reload.reserved_until).to eq(new_deadline)
      expect(client).to have_received(:update_task).with('86ak7rd8j', hash_including(due_date: new_deadline.to_i * 1000))
    end

    # The trail separates the first hold from a renewal, which is what the
    # report needs to show a deal that has been pushed twice.
    it 'records a renewal apart from the first reservation' do
      reserve
      reserve(quote, 12.days.from_now)

      expect(quote.events.pluck(:event)).to eq(%w[reserved reservation_renewed])
    end
  end

  describe 'refusals' do
    it 'refuses a reservation with no date' do
      expect { reserve(quote, nil) }.to raise_error(ArgumentError, /data de vencimento/)
    end

    it 'refuses a date already in the past' do
      expect { reserve(quote, 1.day.ago) }.to raise_error(ArgumentError, /futuro/)
    end
  end
end
