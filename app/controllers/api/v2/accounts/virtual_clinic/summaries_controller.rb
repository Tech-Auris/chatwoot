# Which of Helena's summaries the person wants (daily, weekly, monthly) and
# at what hour. Only administrators and managers: they have her numbers.
class Api::V2::Accounts::VirtualClinic::SummariesController < Api::V1::Accounts::BaseController
  before_action { authorize :virtual_clinic, :ai_team_manager? }

  def show
    render json: payload(summary)
  end

  def update
    record = summary
    record.update!(summary_params)
    render json: payload(record)
  end

  private

  def summary
    Current.account.virtual_clinic_summaries.find_or_initialize_by(user: Current.user)
  end

  def summary_params
    params.permit(:daily, :weekly, :monthly, :hour)
  end

  def payload(record)
    record.slice(:daily, :weekly, :monthly, :hour)
  end
end
