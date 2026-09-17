# Writes the fourteen ClickUp custom fields the sales team fills by hand today
# on every deal that closes, and flips the task status to "negócio fechado"
# once the token card is settled. Runs off the pipeline task the quote already
# points at (`SalesQuote#clickup_task_id`), so no lookup is needed.
#
# The service is safe to call more than once — every write is idempotent from
# ClickUp's point of view (setting a field to what it already holds is a
# no-op). The Sidekiq job that wraps it retries on transient failures.
class Sales::ClickupCrmSyncService
  # ClickUp custom field IDs, taken from the pipeline list. If any of these
  # changes on the CK side (renamed, reset), the whole write goes silently
  # against a stale field, so keep them in one place.
  FIELDS = {
    plan: 'ece3b982-41ed-475f-83c9-de86a0deead9',
    closed_at: '75f740e8-0047-4166-b3e7-d24f032b593e',
    payment_method: 'ae3665e7-b7a0-4a0d-8405-f23a042520f2',
    responsible_name: '41730d40-75a3-43dc-b39c-f35a4011fe06',
    channel_count: '604e10aa-bd75-4986-b6ef-96cd2f381b14',
    professional_count: '2d473b2b-1e90-4cd9-a883-2f9eb54916bf',
    unit_count: '243a2241-3094-4917-b1be-4ba20af88f68',
    custom_dev_count: '494ef081-284d-49b1-998a-50d187a58d1e',
    unit_setup_count: '92301faf-3580-4af2-8f43-e42557943780',
    setup_addons: '8947b818-8c0c-4e13-aa04-89a8e63f107c',
    total_paid: '9641fd48-c3b3-4562-ae3a-a20456d1db57',
    subscription_value: '9bfcf18e-77e7-44e1-817d-bff1f1be6926',
    implementation_value: 'c1175bc5-46e5-4f77-b6d9-a063a558092e',
    subscription_discount: 'ef450ac5-5537-4f83-a28c-d29cece26c61'
  }.freeze

  # Dropdown options on the "Plano" field.
  PLAN_OPTIONS = {
    'monthly' => '6f769975-3579-4c69-bb3d-fbd82db21db4',
    'semiannual' => '17f325cd-2f70-487c-9fb7-cf3c9c643a4f',
    'annual' => '0708341c-2eec-49be-b471-ce80994236ef'
  }.freeze

  # Multi-select options on the "Adicionais de Setup" field, keyed by the
  # Stripe product id we sold to identify each option.
  SETUP_ADDON_OPTIONS = {
    'prod_VEfJKxVbBhF2Xl' => 'e787ba96-e509-4766-b55b-b36295368ef1', # Implantação Guiada
    'prod_VEfIAj5QnI3OMV' => 'bcb77b79-1f3b-443f-a369-55b9d64839d3', # Config. de Integração API
    'prod_UFkJIYgoIksh1w' => 'fb6f7748-7d90-485e-87d5-4c4060f5cc5b', # Desenv. de Integração API
    'prod_VEfKJbd6SmlzZL' => '961dbc4a-ea0a-4f85-bab7-7b212e1568db'  # Configuração de API Meta
  }.freeze

  # Standalone numeric-field products, matched by Stripe product id.
  CUSTOM_DEV_PRODUCT_ID = 'prod_VEfLlaYCZDrjul'.freeze
  UNIT_SETUP_PRODUCT_ID = 'prod_VEfJCsnsDSPxeZ'.freeze

  # The base plan already ships with these — the CK field counts the total,
  # so the item quantities are summed on top of it.
  BASE_CHANNELS = 2
  BASE_PROFESSIONALS = 1
  BASE_UNITS = 1

  # Add-on line names as they appear on `SalesQuoteItem#name` (canonical
  # snapshot at proposal-creation time, kept stable in the DB).
  CHANNEL_ADDON_NAME = 'Adicional de Canal'.freeze
  PROFESSIONAL_ADDON_NAME = 'Adicional de Profissional'.freeze
  UNIT_ADDON_NAME = 'Adicional de Unidade'.freeze

  # Exact status label on the pipeline list — case sensitive.
  CLOSED_STATUS = 'negócio fechado'.freeze

  def initialize(quote:, client: nil)
    @quote = quote
    @client = client
  end

  # Writes the fourteen fields on the pipeline task once the money is in. The
  # values mirror the checklist finance runs by hand today after each sale.
  def sync_paid_fields! # rubocop:disable Metrics/AbcSize
    return unless task_id?

    write_field(:plan, plan_option_id)
    write_field(:closed_at, closed_at_epoch_ms)
    write_field(:payment_method, payment_method_label)
    write_field(:responsible_name, quote.prospect_name)
    write_field(:channel_count, channel_count)
    write_field(:professional_count, professional_count)
    write_field(:unit_count, unit_count)
    write_field(:custom_dev_count, custom_dev_count)
    write_field(:unit_setup_count, unit_setup_count)
    write_field(:setup_addons, setup_addons_body)
    write_field(:total_paid, currency(quote.total_amount))
    write_field(:subscription_value, currency(subscription_monthly_value_cents))
    write_field(:implementation_value, currency(implementation_value_cents))
    write_field(:subscription_discount, currency(quote.discount_amount))

    quote.events.create!(event: 'clickup_crm_paid_fields_synced', metadata: { task_id: task_id })
  end

  # Flips the pipeline task to "negócio fechado" — the last step of the
  # closing checklist, ran after the token card is saved (or waived).
  def mark_closed!
    return unless task_id?

    clickup.update_task(task_id, status: CLOSED_STATUS)
    quote.events.create!(event: 'clickup_crm_status_closed', metadata: { task_id: task_id, status: CLOSED_STATUS })
  end

  private

  attr_reader :quote

  def clickup
    @clickup ||= @client || Integrations::Clickup::Client.new
  end

  def task_id
    quote.clickup_task_id
  end

  def task_id?
    quote.clickup_task_id.present?
  end

  # Skips writes for values that could not be derived (e.g. missing plan
  # option). Every AsaaS/Stripe/PIX confirmation reaches here with a
  # complete quote, so a nil result is either a stub in tests or a data
  # gap worth leaving blank rather than filling with garbage.
  def write_field(key, value)
    return if value.nil?

    clickup.set_custom_field(task_id, FIELDS.fetch(key), value)
  end

  def plan_option_id
    PLAN_OPTIONS[quote.billing_cycle.to_s]
  end

  # ClickUp date fields take epoch milliseconds.
  def closed_at_epoch_ms
    (Time.current.to_f * 1000).to_i
  end

  # The N is locked by the plan (see Sales::CheckoutService.installments_for).
  # PIX is the exception — it is a single transfer with no parcels.
  def payment_method_label
    return 'PIX' if quote.payment_method_pix?
    return 'Cartão' if quote.payment_method_card? && quote.billing_cycle_monthly?

    n = Sales::CheckoutService.installments_for(quote.billing_cycle)
    return "Cartão #{n}x" if quote.payment_method_card?

    "Boleto #{n}x" if quote.payment_method_boleto?
  end

  def channel_count
    additional_quantity(CHANNEL_ADDON_NAME) + BASE_CHANNELS
  end

  def professional_count
    additional_quantity(PROFESSIONAL_ADDON_NAME) + BASE_PROFESSIONALS
  end

  def unit_count
    additional_quantity(UNIT_ADDON_NAME) + BASE_UNITS
  end

  def custom_dev_count
    quote.items.where(stripe_product_id: CUSTOM_DEV_PRODUCT_ID).sum(:quantity)
  end

  def unit_setup_count
    quote.items.where(stripe_product_id: UNIT_SETUP_PRODUCT_ID).sum(:quantity)
  end

  # ClickUp's labels field takes { add: [option_ids] } — additive, does not
  # remove labels already there manually. A sale with none of the four
  # addons writes an empty add list, which is a no-op on CK's side.
  def setup_addons_body
    ids = quote.items.where(stripe_product_id: SETUP_ADDON_OPTIONS.keys)
               .pluck(:stripe_product_id).uniq
               .filter_map { |pid| SETUP_ADDON_OPTIONS[pid] }
    { add: ids }
  end

  def additional_quantity(name)
    quote.items.where(name: name).sum(:quantity)
  end

  # Recurring lines summed and divided by the plan's months — the value the
  # customer pays every month, whether the plan is billed monthly or paid
  # up-front for six or twelve months.
  def subscription_monthly_value_cents
    months = Sales::CheckoutService::CYCLE_MONTHS[quote.billing_cycle&.to_sym].to_i
    return 0 if months.zero?

    recurring_total = quote.items.where.not(recurring_interval: nil).sum('unit_amount * quantity')
    recurring_total / months
  end

  # Non-recurring lines summed — setup fees and one-off implementations.
  def implementation_value_cents
    quote.items.where(recurring_interval: nil).sum('unit_amount * quantity')
  end

  def currency(cents)
    (cents.to_f / 100.0).round(2)
  end
end
