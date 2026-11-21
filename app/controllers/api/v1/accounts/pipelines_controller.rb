# Clinic pipelines (funis da clínica): the list for the selectors, the
# configuration (name, stages, archive, delete) and the board, paginated per
# stage like Api::V1::Accounts::FunnelController.
class Api::V1::Accounts::PipelinesController < Api::V1::Accounts::BaseController
  include PipelineEntriesLoader

  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  before_action :fetch_pipeline, except: [:index, :create]
  before_action :authorize_pipeline

  # Archived pipelines only come with `archived=true` (the list to reactivate
  # them); the selectors get the active ones.
  def index
    scope = Current.account.pipelines.includes(:stages).ordered
    scope = ActiveModel::Type::Boolean.new.cast(params[:archived]) ? scope.where.not(archived_at: nil) : scope.active
    @pipelines = scope.to_a
    @open_counts = Current.account.pipeline_entries.open_entries.where(pipeline_id: @pipelines.map(&:id)).group(:pipeline_id).count
  end

  def show; end

  def create
    stage_params = params.require(:stages)

    ActiveRecord::Base.transaction do
      @pipeline = Current.account.pipelines.create!(name: params.require(:name), position: next_position)
      stage_params.each { |stage| @pipeline.stages.create!(stage.permit(:name, :color).to_h) }
    end
    render :show
  end

  def update
    @pipeline.update!(params.permit(:name))
    render :show
  end

  def destroy
    @pipeline.destroy!
    head :ok
  end

  def archive
    @pipeline.update!(archived_at: Time.current)
    render :show
  end

  def unarchive
    @pipeline.update!(archived_at: nil)
    render :show
  end

  def board
    @stages = @pipeline.stages.to_a
    relation = filtered_entries
    totals = relation.group(:pipeline_stage_id).count
    @stage_totals = totals
    @entries_by_stage = @stages.index_with do |stage|
      (totals[stage.id] || 0).positive? ? page_of(relation.where(pipeline_stage_id: stage.id), 0) : []
    end
    preload_latest_conversations(@entries_by_stage.values.flatten)
  end

  # Next page of one column ("Carregar mais").
  def stage_entries
    @stage = @pipeline.stages.find(params[:stage_id])
    relation = filtered_entries.where(pipeline_stage_id: @stage.id)
    @total = relation.count
    page = [params[:page].to_i, 1].max
    @entries = page_of(relation, (page - 1) * per_page)
    @has_more = ((page - 1) * per_page) + @entries.size < @total
    preload_latest_conversations(@entries)
  end

  private

  def fetch_pipeline
    @pipeline = Current.account.pipelines.find(params[:id])
  end

  def authorize_pipeline
    authorize(@pipeline || Pipeline)
  end

  def next_position
    (Current.account.pipelines.maximum(:position) || -1) + 1
  end

  def page_of(relation, offset)
    relation.includes(:added_by, :loss_reason, contact: { avatar_attachment: :blob })
            .order(stage_entered_at: :desc, id: :desc)
            .offset(offset)
            .limit(per_page)
            .to_a
  end

  def filtered_entries
    relation = @pipeline.entries
    relation = relation.open_entries if ActiveModel::Type::Boolean.new.cast(params[:hide_closed])
    relation = relation.where(source: params[:source]) if PipelineEntry.sources.key?(params[:source])
    relation = relation.where(contact_id: labelled_contact_ids) if params[:label].present?
    relation.where(pipeline_entries: { created_at: entered_between })
  end

  # Filters on the date the contact entered the pipeline.
  def entered_between
    (parse_time(params[:from]) || Time.zone.at(0))..(parse_time(params[:to]) || Time.current)
  end

  def labelled_contact_ids
    Current.account.contacts.tagged_with(params[:label], any: true).select(:id)
  end

  def parse_time(value)
    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  def per_page
    requested = params[:per_page].to_i
    (requested.positive? ? requested : DEFAULT_PER_PAGE).clamp(1, MAX_PER_PAGE)
  end
end
