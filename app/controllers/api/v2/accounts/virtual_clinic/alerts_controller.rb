# What the AI team raised its hand for (VirtualClinic::AlertChecker), for
# administrators and managers, plus each one's own summaries. Opening an
# alert on the map acknowledges it.
class Api::V2::Accounts::VirtualClinic::AlertsController < Api::V1::Accounts::BaseController
  SHOWN = 20

  before_action { authorize :virtual_clinic, :ai_team_manager? }

  def index
    alerts = Current.account.virtual_clinic_alerts.open.seen_by(Current.user).order(created_at: :desc).limit(SHOWN)
    render json: { alerts: alerts.map(&:push_event_data), counts: ::VirtualClinic::AlertBroadcast.counts(Current.account, Current.user) }
  end

  def acknowledge
    Current.account.virtual_clinic_alerts.open.seen_by(Current.user).where(persona: params.require(:persona)).find_each do |alert|
      alert.update!(acknowledged_at: Time.current)
    end
    ::VirtualClinic::AlertBroadcast.new(Current.account).perform
    head :ok
  end
end
