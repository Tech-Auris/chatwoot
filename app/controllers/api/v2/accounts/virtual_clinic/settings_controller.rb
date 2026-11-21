# Clínica virtual settings the clinic administrator controls: the daily
# question cap (Integrations → OpenAI).
class Api::V2::Accounts::VirtualClinic::SettingsController < Api::V1::Accounts::BaseController
  def update
    authorize :virtual_clinic, :update_settings?
    Current.account.update!(settings: Current.account.settings.merge(changes))
    render json: { daily_question_limit: ::VirtualClinic::QuestionLimit.for(Current.account) }
  end

  private

  # Only what was sent changes.
  def changes
    values = {}
    values[::VirtualClinic::QuestionLimit::SETTING] = params[:daily_question_limit].presence&.to_i if params.key?(:daily_question_limit)
    values
  end
end
