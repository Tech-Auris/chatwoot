# Autentique telling us a contract changed: a signature was accepted or
# refused, or the document was finished. The payload only says which document
# moved — its state is read back from the API, which is the source of truth.
#
# Authentication: the webhook secret (Super Admin → Settings → Autentique)
# goes in the URL path, like the Banco Inter webhook — signed webhooks
# (`x-autentique-signature`) are a paid Autentique feature. Without a secret
# configured, every request is refused. Even a forged call only makes us ask
# the API again: nothing in the payload is taken as the contract's state.
class Webhooks::Commercial::AutentiqueController < ActionController::API
  def process_payload
    body = request.body.read
    return head :unauthorized unless authorized?

    contract = SalesContract.find_by(autentique_document_id: document_id(body))
    Sales::ContractStatusService.new(contract).refresh! if contract
    head :ok
  end

  private

  def authorized?
    secret = GlobalConfig.get('AUTENTIQUE_WEBHOOK_SECRET')['AUTENTIQUE_WEBHOOK_SECRET'].to_s
    return false if secret.blank?

    ActiveSupport::SecurityUtils.secure_compare(secret, params[:token].to_s)
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
