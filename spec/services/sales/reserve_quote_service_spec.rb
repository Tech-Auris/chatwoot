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
    allow(client).to receive(:add_comment)
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

  # After a successful reserve, the ClickUp task gets a comment with the
  # copy-paste WhatsApp message so whoever handles the handoff has the
  # text at hand — same wording the Quotes / Reservations screens copy.
  it 'posts the reservation message on the ClickUp task as a comment' do
    reserve

    expect(client).to have_received(:add_comment) do |task_id, text|
      expect(task_id).to eq('86ak7rd8j')
      expect(text).to start_with('Vendedor criou a reserva. Envie a seguinte mensagem para o cliente:')
      expect(text).to include(quote.access_code)
      expect(text).to include(quote.public_token)
    end
  end

  # The comment is a convenience — a hiccup posting it must not fail
  # the reserve nor change what the ClickUp sync reports.
  it 'reserves cleanly when the comment post fails' do
    allow(client).to receive(:add_comment).and_raise(Integrations::Clickup::Client::ProviderUnavailable, 'ClickUp 500')

    result = reserve

    expect(result.quote.reload.status).to eq('reserved')
    expect(result.clickup_synced).to be true
    expect(result.clickup_error).to be_nil
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

  # A `signature` acceptance inherits the reservation's deadline: the prospect
  # has until the reservation expires to sign. Moving the reservation moves
  # the terms deadline with it, so both dates keep telling the same story.
  # A signed row stays frozen — the audit trail is what it was.
  describe 'terms deadline cascade' do
    let(:terms_version) { create(:terms_version) }

    it 'mirrors the reservation deadline onto a pending signature acceptance' do
      pending = create(:terms_acceptance, sales_quote: quote, terms_version: terms_version,
                                          status: :pending, kind: :signature, deadline_at: 3.days.from_now)

      reserve(quote, deadline)

      expect(pending.reload.deadline_at).to be_within(1.second).of(deadline)
    end

    it 'moves the pending deadline on a renewal too' do
      pending = create(:terms_acceptance, sales_quote: quote, terms_version: terms_version,
                                          status: :pending, kind: :signature, deadline_at: 3.days.from_now)
      reserve(quote, deadline)
      new_deadline = 12.days.from_now.change(usec: 0)

      reserve(quote, new_deadline)

      expect(pending.reload.deadline_at).to be_within(1.second).of(new_deadline)
    end

    it 'leaves a signed acceptance alone' do
      signed = create(:terms_acceptance, sales_quote: quote, terms_version: terms_version,
                                         status: :signed, kind: :signature, deadline_at: 3.days.from_now,
                                         signer_name: 'A', signer_email: 'a@b.c', signed_at: Time.current, ip_address: '1.1.1.1')
      original = signed.deadline_at

      reserve(quote, deadline)

      expect(signed.reload.deadline_at).to be_within(1.second).of(original)
    end
  end
end
