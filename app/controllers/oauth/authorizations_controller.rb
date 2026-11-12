# Entry point of the authorization code flow. The dashboard login is token
# based (no Rails session), so the consent happens on the SPA: a valid request
# is handed over to /app/oauth/consent; an invalid one is answered here,
# back to the client when its redirect URI is trusted.
class Oauth::AuthorizationsController < ActionController::API
  PARAMS = %i[response_type client_id redirect_uri scope state code_challenge code_challenge_method].freeze

  def new
    pre_auth = Doorkeeper::OAuth::PreAuthorization.new(Doorkeeper.config, authorization_params)
    return redirect_to("/app/oauth/consent?#{authorization_params.to_query}", allow_other_host: false) if pre_auth.authorizable?

    error = pre_auth.error_response
    return redirect_to(error.redirect_uri, allow_other_host: true) if error.redirectable? && pre_auth.client_valid?

    render json: error.body, status: :bad_request
  end

  private

  def authorization_params
    params.permit(*PARAMS).to_h
  end
end
