# "Horário da IA desligada" of an inbox: whether it is on, the team that takes
# the conversations and the weekday ranges. Administrators and managers.
class Api::V1::Accounts::InboxAiSchedulesController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox

  def show; end

  def update
    ActiveRecord::Base.transaction do
      @inbox.update!(ai_schedule_enabled: params[:enabled], ai_schedule_team: team)
      @inbox.ai_off_hours.destroy_all
      hours_params.each { |hour| @inbox.ai_off_hours.create!(hour) }
    end
    render :show
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :update?
  end

  def team
    Current.account.teams.find(params[:team_id]) if params[:team_id].present?
  end

  def hours_params
    Array(params[:hours]).map do |hour|
      { day_of_week: hour[:day_of_week], from_minutes: minutes(hour[:from]), to_minutes: minutes(hour[:to]) }
    end
  end

  # "08:30" → 510; "24:00" closes the day.
  def minutes(time)
    hours, mins = time.to_s.split(':').map(&:to_i)
    (hours * 60) + mins.to_i
  end
end
