class Api::V2::Accounts::SummaryReportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :prepare_builder_params,
                only: [:agent, :team, :inbox, :label, :origem, :channel, :funnel, :funnel_conversion, :funnel_conversion_campaigns,
                       :funnel_conversion_drilldown, :campaign_analytics]

  # A report that outgrows the statement timeout on a large account answers
  # with a clear error (tagged with the account) instead of a bare 500.
  # Around action (not rescue_from) so the account and its locale are still set.
  around_action :handle_report_timeout

  def agent
    render_report_with(V2::Reports::AgentSummaryBuilder, type: :agent)
  end

  def team
    render_report_with(V2::Reports::TeamSummaryBuilder, type: :team)
  end

  def inbox
    render_report_with(V2::Reports::InboxSummaryBuilder, type: :inbox)
  end

  def label
    render_report_with(V2::Reports::LabelSummaryBuilder)
  end

  def origem
    render_report_with(V2::Reports::OrigemSummaryBuilder)
  end

  def channel
    return render_could_not_create_error(I18n.t('errors.reports.date_range_too_long')) if date_range_too_long?

    render_report_with(V2::Reports::ChannelSummaryBuilder)
  end

  def funnel
    render_report_with(V2::Reports::FunnelSummaryBuilder)
  end

  def funnel_conversion
    render_report_with(V2::Reports::FunnelConversionBuilder)
  end

  def funnel_conversion_campaigns
    render json: V2::Reports::FunnelConversionBuilder.new(account: Current.account, params: @builder_params).campaign_breakdown
  end

  # Also serves Marketing → Analytics, whose columns (`metric`) count one ad's
  # conversations the way that report does.
  def funnel_conversion_drilldown
    builder_params = @builder_params.merge(params.permit(:stage_key, :kind, :loss_reason_id, :source_id, :metric, :page).to_h.symbolize_keys)
    builder_class = params[:metric].present? ? V2::Reports::CampaignAnalyticsDrilldownBuilder : V2::Reports::FunnelConversionDrilldownBuilder
    render json: builder_class.new(account: Current.account, params: builder_params).build
  rescue V2::Reports::FunnelConversionDrilldownBuilder::UnknownStage
    render json: { error: 'Unknown funnel stage' }, status: :unprocessable_entity
  end

  def campaign_analytics
    render_report_with(V2::Reports::CampaignAnalyticsBuilder)
  end

  private

  def handle_report_timeout
    yield
  rescue ActiveRecord::QueryCanceled => e
    ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
    render json: { error: I18n.t('errors.reports.timeout') }, status: :service_unavailable
  end

  def check_authorization
    authorize :report, :view?
  end

  def prepare_builder_params
    @builder_params = {
      since: permitted_params[:since],
      until: permitted_params[:until],
      business_hours: ActiveModel::Type::Boolean.new.cast(permitted_params[:business_hours]),
      # Funnel reports honor these three; other builders quietly ignore them.
      inbox_id: permitted_params[:inbox_id],
      # The Início page opens the funnel drill-down over several caixas.
      inbox_ids: permitted_params[:inbox_ids].presence,
      label: permitted_params[:label],
      origem: permitted_params[:origem]
    }
  end

  def render_report_with(builder_class, type: nil)
    builder_params = type.present? ? @builder_params.merge(type: type) : @builder_params
    builder = builder_class.new(account: Current.account, params: builder_params)
    render json: builder.build
  end

  def permitted_params
    params.permit(:since, :until, :business_hours, :inbox_id, :label, :origem, inbox_ids: [])
  end

  def date_range_too_long?
    return false if permitted_params[:since].blank? || permitted_params[:until].blank?

    since_time = Time.zone.at(permitted_params[:since].to_i)
    until_time = Time.zone.at(permitted_params[:until].to_i)
    (until_time - since_time) > 6.months
  end
end
