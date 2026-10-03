# Autentique telling us a contract changed: a signature was accepted or
# refused, or the document was finished. The payload only says which document
# moved — its state is read back from the API, which is the source of truth.
#
# Signature: `x-autentique-signature` is the HMAC-SHA256 of the raw body with
# the webhook secret (Super Admin → Settings → Autentique). Without a secret
# configured, every request is refused.
class Webhooks::Commercial::AutentiqueController < ActionController::API
  def process_payload
    body = request.body.read
    return head :unauthorized unless authorized?(body)

    contract = SalesContract.find_by(autentique_document_id: document_id(body))
    Sales::ContractStatusService.new(contract).refresh! if contract
    head :ok
  end

  private

  def authorized?(body)
    secret = GlobalConfig.get('AUTENTIQUE_WEBHOOK_SECRET')['AUTENTIQUE_WEBHOOK_SECRET'].to_s
    return false if secret.blank?

    expected = OpenSSL::HMAC.hexdigest('SHA256', secret, body)
    ActiveSupport::SecurityUtils.secure_compare(expected, request.headers['x-autentique-signature'].to_s)
  end

  # Document events carry the document itself; signature events carry the
  # signature with its document.
  def document_id(body)
    object = JSON.parse(body).dig('event', 'data', 'object') || {}
    object.dig('document', 'id') || object['document_id'] || object['document'].presence || object['id']
  rescue JSON::ParserError
    nil
  end
end
