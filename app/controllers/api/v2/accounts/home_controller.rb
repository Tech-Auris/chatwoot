# The Início page: the day summary and the indicator cards. Every user of an
# account with the page switched on can open it; the builder narrows the
# numbers to the caixas they can see.
class Api::V2::Accounts::HomeController < Api::V1::Accounts::BaseController
  before_action :ensure_home_enabled

  def show
    render json: builder.build
  end

  def drilldown
    render json: builder.drilldown(metric: params[:metric], page: params[:page])
  rescue V2::Reports::Home::Drilldown::UnknownMetric
    render json: { error: 'Unknown metric' }, status: :unprocessable_entity
  end

  private

  def builder
    V2::Reports::HomeBuilder.new(account: Current.account, account_user: Current.account_user, params: home_params)
  end

  def ensure_home_enabled
    head :not_found unless Current.account.home_enabled?
  end

  def home_params
    params.permit(:since, :until, :origem, inbox_ids: [])
  end
end
