require 'rails_helper'

RSpec.describe 'Super admin MFA challenge', type: :request do
  let(:super_admin) { create(:super_admin, password: 'Password1!') }

  before do
    skip('Skipping since MFA is not configured in this environment') unless Chatwoot.encryption_configured?
    super_admin.enable_two_factor!
    super_admin.update!(otp_required_for_login: true)
    Redis::Alfred.delete("SUPER_ADMIN_MFA_FAILURES::#{super_admin.id}")
    post '/super_admin/sign_in', params: { super_admin: { email: super_admin.email, password: 'Password1!' } }
  end

  it 'signs in with a valid code' do
    post '/super_admin/sessions/mfa_challenge', params: { otp_code: super_admin.current_otp }

    expect(response).to redirect_to('/super_admin/users')
  end

  it 'asks for the code again after a wrong one' do
    post '/super_admin/sessions/mfa_challenge', params: { otp_code: '000000' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'sends the admin back to the password step after too many wrong codes' do
    SuperAdmin::Sessions::MfaChallengeController::MAX_FAILED_ATTEMPTS.times do
      post '/super_admin/sessions/mfa_challenge', params: { otp_code: '000000' }
    end

    expect(response).to redirect_to(new_super_admin_session_path)
    expect(flash[:error]).to eq(I18n.t('errors.mfa.too_many_attempts'))
  end

  it 'keeps the lock when the admin signs in again and sends the right code' do
    SuperAdmin::Sessions::MfaChallengeController::MAX_FAILED_ATTEMPTS.times do
      post '/super_admin/sessions/mfa_challenge', params: { otp_code: '000000' }
    end
    post '/super_admin/sign_in', params: { super_admin: { email: super_admin.email, password: 'Password1!' } }

    post '/super_admin/sessions/mfa_challenge', params: { otp_code: super_admin.current_otp }

    expect(response).to redirect_to(new_super_admin_session_path)
  end

  it 'expires the code step after a few minutes' do
    travel(SuperAdmin::Sessions::MfaChallengeController::CHALLENGE_TTL + 1.second) do
      post '/super_admin/sessions/mfa_challenge', params: { otp_code: super_admin.current_otp }
    end

    expect(response).to redirect_to(new_super_admin_session_path)
    expect(flash[:error]).to eq(I18n.t('errors.mfa.challenge_expired'))
  end
end
