# Turns the monthly token-usage spreadsheet into one invoice per customer.
#
# The finance team exports usage per account (text messages, media/transcription
# answers, audio messages); each category is billed at a catalog price, so the
# invoice reproduces what they issue by hand today: quantity × unit price, one
# line per category.
#
# `preview` computes the money without touching Stripe, which is the whole point
# of the flow — the team reconciles the totals before a single invoice exists.
class Financial::TokenBillingService
  CATEGORIES = %i[text media audio].freeze

  class MissingPrices < StandardError; end

  attr_reader :prices

  # `prices` maps each category to a Stripe price id.
  def initialize(prices:, client: nil)
    @prices = prices.symbolize_keys
    @client = client
  end

  def preview(rows)
    catalog = price_catalog
    lines = rows.map { |row| build_line(row, catalog) }

    {
      lines: lines,
      total_amount: lines.sum { |line| line[:billable] ? line[:total_amount] : 0 },
      billable_count: lines.count { |line| line[:billable] },
      currency: catalog.values.first&.currency || 'brl'
    }
  end

  # Issues one invoice per billable row. A failure on one customer must not
  # abort the batch: the remaining invoices still go out and the report says
  # exactly which ones did not.
  def perform(rows, description: nil, days_until_due: nil, period: nil)
    preview(rows)[:lines].map do |line|
      next skipped_result(line) unless line[:billable]

      issue(line, description, days_until_due, period)
    end
  end

  private

  def client
    @client ||= Integrations::Stripe::Client.new
  end

  # Prices are read once and kept: the amount shown in the preview has to be the
  # same amount charged, and re-reading per row would let a price edited midway
  # bill something the team never saw.
  def price_catalog
    @price_catalog ||= begin
      ids = prices.values_at(*CATEGORIES).compact_blank
      raise MissingPrices, 'Escolha o preço de cada categoria antes de continuar' if ids.size < CATEGORIES.size

      found = client.list_prices.data.index_by(&:id)
      missing = ids.reject { |id| found.key?(id) }
      raise MissingPrices, "Preço não encontrado no Stripe: #{missing.join(', ')}" if missing.any?

      CATEGORIES.index_with { |category| found[prices[category]] }
    end
  end

  def build_line(row, catalog)
    account = Account.find_by(id: row[:account_id])
    items = build_items(row, catalog)

    {
      account_id: row[:account_id],
      account_name: account&.name || row[:account_name],
      quantities: CATEGORIES.index_with { |category| quantity_for(row, category) },
      items: items,
      total_amount: items.sum { |item| item[:amount] },
      # Everything that stops this row from becoming an invoice, said plainly so
      # the team fixes the spreadsheet instead of guessing.
      issue: row_issue(account, items),
      billable: row_issue(account, items).nil?
    }
  end

  def row_issue(account, items)
    return 'conta não encontrada' if account.nil?
    return 'conta sem cliente do Stripe vinculado' if account.stripe_customer_id.blank?
    return 'consumo zerado' if items.empty?

    nil
  end

  def build_items(row, catalog)
    CATEGORIES.filter_map do |category|
      quantity = quantity_for(row, category)
      next if quantity.zero?

      price = catalog[category]
      { category: category, price_id: price.id, quantity: quantity, unit_amount: price.unit_amount,
        amount: price.unit_amount.to_i * quantity, description: price_description(price) }
    end
  end

  def quantity_for(row, category)
    row[category].to_i.clamp(0, Float::INFINITY)
  end

  def price_description(price)
    price.try(:nickname).presence || price.id
  end

  def issue(line, description, days_until_due, period)
    account = Account.find(line[:account_id])
    invoice = client.create_invoice(
      customer_id: account.stripe_customer_id,
      items: line[:items].map { |item| { price_id: item[:price_id], quantity: item[:quantity] } },
      days_until_due: days_until_due.presence || Integrations::Stripe::Client::DEFAULT_DAYS_UNTIL_DUE,
      description: description,
      metadata: token_metadata(period)
    )

    line.slice(:account_id, :account_name, :total_amount)
        .merge(status: 'issued', invoice_id: invoice.id, invoice_number: invoice.try(:number),
               invoice_url: invoice.try(:hosted_invoice_url))
  rescue Integrations::Stripe::Client::Error => e
    line.slice(:account_id, :account_name, :total_amount).merge(status: 'failed', error: e.message)
  end

  # Stamped so a token invoice is recognizable later — both to report on the
  # batch and to notice a period billed twice.
  def token_metadata(period)
    { Integrations::Stripe::Client::BILLING_SOURCE_METADATA_KEY => 'token_batch' }.tap do |metadata|
      metadata[Integrations::Stripe::Client::BILLING_PERIOD_METADATA_KEY] = period if period.present?
    end
  end

  def skipped_result(line)
    line.slice(:account_id, :account_name, :total_amount).merge(status: 'skipped', error: line[:issue])
  end
end
