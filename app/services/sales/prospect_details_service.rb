# Records what the prospect filled in on the public page, and keeps the ClickUp
# task in step with it.
#
# The phone is the field that matters twice: it is what the sales team calls,
# and it is half of what opens the proposal link next time. So it is written
# back to the task whenever the prospect gives us one the task does not have,
# or corrects the one it does.
class Sales::ProspectDetailsService
  PHONE_FIELD_ID = Sales::ClickupProspectSearchService::PHONE_FIELD_ID

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
    save_details!

    error = phone_changed?(previous_phone) ? sync_phone : nil
    quote.events.create!(event: 'details_filled', metadata: { clickup_synced: error.nil?, clickup_error: error }.compact)

    Result.new(quote: quote, clickup_synced: error.nil?, clickup_error: error)
  end

  private

  def save_details!
    quote.update!(
      prospect_name: attributes[:name],
      prospect_email: attributes[:email],
      prospect_phone: attributes[:phone],
      prospect_document: attributes[:document],
      # The gate follows the number the prospect confirmed, otherwise the next
      # visit would ask for digits they no longer use.
      verification_phone_last4: digits(attributes[:phone]).last(4).presence
    )
  end

  attr_reader :quote, :attributes

  def client
    @client ||= Integrations::Clickup::Client.new
  end

  def phone_changed?(previous_phone)
    digits(attributes[:phone]).present? && digits(attributes[:phone]) != previous_phone
  end

  def sync_phone
    return 'ClickUp não está configurado' unless client.configured?

    client.set_custom_field(quote.clickup_task_id, PHONE_FIELD_ID, attributes[:phone])
    nil
  rescue Integrations::Clickup::Client::Error => e
    e.message
  end

  def digits(value)
    value.to_s.gsub(/\D/, '')
  end
end
