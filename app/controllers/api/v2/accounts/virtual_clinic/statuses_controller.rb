# Live status of the AI team, polled by the Clínica virtual every 30 s.
class Api::V2::Accounts::VirtualClinic::StatusesController < Api::V1::Accounts::BaseController
  def show
    authorize :virtual_clinic, :ai_team_visible?
    render json: ::VirtualClinic::StatusBuilder.new(account: Current.account, account_user: Current.account_user).build
  end
end
