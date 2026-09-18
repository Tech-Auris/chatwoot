# AsaaS telling us a payment on one of our instalment books changed state:
# the money arrived, the settlement window closed, a boleto went past its
# due date, or a payment was refunded/removed. Without this endpoint the
# finance team clicks through the six or twelve parcels of every carnê by
# hand — this replaces those clicks with the same server-side flow the
# manual button already runs, on the parcel that first lands.
#
# Signature: AsaaS is asked, on the webhook screen, to send a token on the
# `asaas-access-token` header — the same value is kept here in
# InstallationConfig. A request without a matching header is refused so
# nobody outside AsaaS can mark a sale as paid.
class Webhooks::Commercial::AsaasController < ActionController::API
  def process_payload
    return head :unauthorized unless authorized?

    event, payment = parse_event
    return head :bad_request if event.blank?

    Webhooks::Asaas::PaymentEventHandler.new(event: event, payment: payment).perform
    head :ok
  end

  private

  def authorized?
    expected = GlobalConfig.get('ASAAS_WEBHOOK_TOKEN')['ASAAS_WEBHOOK_TOKEN'].to_s
    return false if expected.blank?

    ActiveSupport::SecurityUtils.secure_compare(expected, request.headers['asaas-access-token'].to_s)
  end

  def parse_event
    body = request.body.read
    parsed = JSON.parse(body)
    [parsed['event'], parsed['payment']]
  rescue JSON::ParserError
    [nil, nil]
  end
end
