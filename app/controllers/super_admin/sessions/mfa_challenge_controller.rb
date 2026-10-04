class SuperAdmin::Sessions::MfaChallengeController < ApplicationController
  include SuperAdminHomeRedirect

  layout false

  # A stolen password alone must not be enough to guess the 6-digit code: the
  # step expires, and a few wrong codes lock it and send the admin back to the
  # password step. The failure count lives in Redis, keyed by the admin, so
  # replaying an older session cookie doesn't reset it.
  CHALLENGE_TTL = 5.minutes
  MAX_FAILED_ATTEMPTS = 5
  LOCKOUT_PERIOD = 15.minutes

  before_action :load_pending_super_admin
  before_action :ensure_mfa_feature_available

  def show; end

  def create
    return restart_sign_in('errors.mfa.too_many_attempts') if locked_out?

    if authenticate_otp(params[:otp_code]) || authenticate_backup_code(params[:backup_code])
      clear_pending_mfa
      Redis::Alfred.delete(failures_key)
      sign_in(:super_admin, @pending_super_admin)
      flash.discard
      redirect_to super_admin_home_path_for(@pending_super_admin)
    else
      register_failure
      return restart_sign_in('errors.mfa.too_many_attempts') if locked_out?

      flash.now[:error] = I18n.t('errors.mfa.invalid_code')
      render :show, status: :unauthorized
    end
  end

  private

  def load_pending_super_admin
    pending_id = session[:super_admin_pending_mfa_id]
    @pending_super_admin = SuperAdmin.find_by(id: pending_id)
    return restart_sign_in unless @pending_super_admin&.mfa_enabled?

    restart_sign_in('errors.mfa.challenge_expired') if challenge_expired?
  end

  def challenge_expired?
    Time.zone.at(session[:super_admin_pending_mfa_at].to_i) < CHALLENGE_TTL.ago
  end

  def failures_key
    "SUPER_ADMIN_MFA_FAILURES::#{@pending_super_admin.id}"
  end

  def register_failure
    Redis::Alfred.incr(failures_key)
    Redis::Alfred.expire(failures_key, LOCKOUT_PERIOD.to_i)
  end

  def locked_out?
    Redis::Alfred.get(failures_key).to_i >= MAX_FAILED_ATTEMPTS
  end

  def restart_sign_in(error_key = nil)
    clear_pending_mfa
    redirect_to new_super_admin_session_path, flash: { error: error_key && I18n.t(error_key) }
  end

  def clear_pending_mfa
    session.delete(:super_admin_pending_mfa_id)
    session.delete(:super_admin_pending_mfa_at)
  end

  def ensure_mfa_feature_available
    return if Chatwoot.mfa_enabled?

    restart_sign_in
  end

  def authenticate_otp(otp_code)
    return false if otp_code.blank?

    Mfa::AuthenticationService.new(user: @pending_super_admin, otp_code: otp_code).authenticate
  end

  def authenticate_backup_code(backup_code)
    return false if backup_code.blank?

    Mfa::AuthenticationService.new(user: @pending_super_admin, backup_code: backup_code).authenticate
  end
end
