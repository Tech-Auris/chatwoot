# ERP → Agenda: the clinic's agenda for up to a week, read live from its ERP
# or calendar (see Agenda::Source). Read only.
class Api::V1::Accounts::AgendaController < Api::V1::Accounts::BaseController
  before_action :set_source, :set_period

  def show
    render json: @source.agenda(@from, @to).merge(from: @from.iso8601, to: @to.iso8601)
  rescue Agenda::Source::Error => e
    render json: { error: I18n.t('agenda.errors.source_failed', error: e.message) }, status: :bad_gateway
  end

  private

  def set_source
    @source = Agenda::Source.for(Current.account)
    render json: { error: I18n.t('agenda.errors.not_configured') }, status: :not_found unless @source
  end

  def set_period
    @from = Date.iso8601(params[:from].to_s)
    @to = Date.iso8601(params[:to].to_s)
    return if @from <= @to && (@to - @from) < Agenda::Source::MAX_DAYS

    render_invalid_period
  rescue Date::Error
    render_invalid_period
  end

  def render_invalid_period
    render json: { error: I18n.t('agenda.errors.invalid_period', days: Agenda::Source::MAX_DAYS) }, status: :unprocessable_entity
  end
end
