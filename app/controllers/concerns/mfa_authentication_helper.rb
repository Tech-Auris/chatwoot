module MfaAuthenticationHelper
  extend ActiveSupport::Concern

  private

  # Password reset and email confirmation must not mint a session for a user
  # whose second factor has not been presented: send them to sign in instead.
  def mfa_sign_in_required?(user)
    user.mfa_enabled?
  end

  def render_mfa_sign_in_required
    render json: {
      message: I18n.t('messages.mfa_sign_in_required'),
      redirect_url: '/app/login'
    }, status: :ok
  end
end
