class Api::V1::Accounts::ConversionEventsController < Api::V1::Accounts::BaseController
  before_action :fetch_event, except: [:index, :create]
  before_action :check_authorization

  def index
    @events = policy_scope(Current.account.conversion_events).order(:name)
  end

  def show; end

  def create
    @event = Current.account.conversion_events.create!(permitted_params)
    render :show
  end

  def update
    @event.update!(permitted_params)
    render :show
  end

  def destroy
    @event.destroy!
    head :ok
  end

  private

  def fetch_event
    @event = Current.account.conversion_events.find(params[:id])
  end

  def permitted_params
    params.permit(:name, :trigger_type, :meta_event_name, :google_event_name, :enabled,
                  trigger_config: {})
  end
end
