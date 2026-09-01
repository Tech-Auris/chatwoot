# Records what the prospect filled in on the public page, and keeps the ClickUp
# task in step with it.
#
# The phone is the field that matters twice: it is what the sales team calls,
# and it is half of what opens the proposal link next time. So it is written
# back to the task whenever the prospect gives us one the task does not have,
# or corrects the one it does.
class Sales::ProspectDetailsService
  PHONE_FIELD_ID = Sales::ClickupProspectSearchService::PHONE_FIELD_ID
  CLINIC_FIELD_ID = Sales::ClickupProspectSearchService::CLINIC_FIELD_ID

  Result = Struct.new(:quote, :clickup_synced, :clickup_error, keyword_init: true)

  def initialize(quote:, attributes:, client: nil)
    @quote = quote
    # `to_h` first: ActionController::Parameters has no `symbolize_keys`, and a
    # controller handing its params straight in is the normal caller here.
    @attributes = attributes.to_h.symbolize_keys
    @client = client
  end

  def perform
    previous_phone = digits(quote.prospect_phone)
    previous_clinic = quote.company_name.to_s.strip
    save_details!

    error = [sync_phone_if_changed(previous_phone), sync_clinic_if_changed(previous_clinic)].compact.first
    quote.events.create!(event: 'details_filled', metadata: { clickup_synced: error.nil?, clickup_error: error }.compact)

    Result.new(quote: quote, clickup_synced: error.nil?, clickup_error: error)
  end

  private

  # Statuses whose lifecycle position is behind the confirmation step —
  # signed/paid/converted already imply the details are in, and
  # expired/cancelled are terminal, so none of them should be moved.
  ADVANCEABLE_STATUSES = %w[draft reserved].freeze

  def save_details!
    quote.update!(
      prospect_name: attributes[:name],
      prospect_email: attributes[:email],
      prospect_phone: attributes[:phone],
      prospect_document: attributes[:document],
      # The clinic names the account that will be created, so it is asked here
      # rather than read from a ClickUp field that is still empty at this point.
      company_name: attributes[:company_name],
      billing_name: attributes[:billing_name],
      company_document: attributes[:company_document],
      # The gate follows the number the prospect confirmed, otherwise the next
      # visit would ask for digits they no longer use.
      verification_phone_last4: digits(attributes[:phone]).last(4).presence
    )

    advance_status_to_details_confirmed!
  end

  def advance_status_to_details_confirmed!
    return unless quote.details_complete?
    return unless ADVANCEABLE_STATUSES.include?(quote.status)

    quote.update!(status: :details_confirmed)
  end

  attr_reader :quote, :attributes

  def client
    @client ||= Integrations::Clickup::Client.new
  end

  def sync_phone_if_changed(previous_phone)
    return nil if digits(attributes[:phone]).blank? || digits(attributes[:phone]) == previous_phone

    write_field(PHONE_FIELD_ID, attributes[:phone])
  end

  # The clinic is what the sales team and the ops team call the customer, and
  # the task is where they look for it.
  def sync_clinic_if_changed(previous_clinic)
    clinic = attributes[:company_name].to_s.strip
    return nil if clinic.blank? || clinic == previous_clinic

    write_field(CLINIC_FIELD_ID, clinic)
  end

  def write_field(field_id, value)
    return 'ClickUp não está configurado' unless client.configured?

    client.set_custom_field(quote.clickup_task_id, field_id, value)
    nil
  rescue Integrations::Clickup::Client::Error => e
    e.message
  end

  def digits(value)
    value.to_s.gsub(/\D/, '')
  end
end
