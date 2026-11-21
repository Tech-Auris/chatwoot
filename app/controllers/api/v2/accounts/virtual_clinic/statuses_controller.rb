# Live status of the AI team, polled by the Clínica virtual every 30 s.
# Agents don't get the numbers of the restricted teammates (the manager).
class Api::V2::Accounts::VirtualClinic::StatusesController < Api::V1::Accounts::BaseController
  def show
    authorize :virtual_clinic, :ai_team_visible?
    status = ::VirtualClinic::StatusBuilder.new(account: Current.account, account_user: Current.account_user).build
    policy = VirtualClinicPolicy.new(pundit_user, :virtual_clinic)
    render json: policy.ai_team_manager? ? status : status.reject { |key, _| ::VirtualClinic::Persona.find!(key.to_s).restricted? }
  end
end
