# Clínica virtual settings the clinic administrator controls.
class Api::V2::Accounts::VirtualClinic::SettingsController < Api::V1::Accounts::BaseController
  def update
    authorize :virtual_clinic, :update_settings?
    limit = params[:daily_question_limit].presence&.to_i
    Current.account.update!(settings: Current.account.settings.merge(::VirtualClinic::QuestionLimit::SETTING => limit))
    render json: { daily_question_limit: limit }
  end
end
