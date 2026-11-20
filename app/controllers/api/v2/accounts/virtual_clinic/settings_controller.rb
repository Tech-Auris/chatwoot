# Clínica virtual settings the clinic administrator controls: the daily
# question cap (Integrations → OpenAI) and Helena's good morning summary.
class Api::V2::Accounts::VirtualClinic::SettingsController < Api::V1::Accounts::BaseController
  def update
    authorize :virtual_clinic, :update_settings?
    Current.account.update!(settings: Current.account.settings.merge(changes))
    render json: { daily_question_limit: ::VirtualClinic::QuestionLimit.for(Current.account),
                   daily_summary: Current.account.settings[::VirtualClinic::Alerts::DailySummary::SETTING] == true }
  end

  private

  # Only what was sent changes.
  def changes
    values = {}
    values[::VirtualClinic::QuestionLimit::SETTING] = params[:daily_question_limit].presence&.to_i if params.key?(:daily_question_limit)
    if params.key?(:daily_summary)
      values[::VirtualClinic::Alerts::DailySummary::SETTING] = ActiveModel::Type::Boolean.new.cast(params[:daily_summary])
    end
    values
  end
end
