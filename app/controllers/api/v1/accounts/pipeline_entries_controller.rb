# Moves a contact between the stages of a clinic pipeline, takes it out of the
# pipeline and shows the history of a pass.
class Api::V1::Accounts::PipelineEntriesController < Api::V1::Accounts::BaseController
  include PipelineEntriesLoader

  before_action :fetch_entry
  before_action -> { authorize(@entry) }

  def move
    stage = @entry.pipeline.stages.find(params.require(:pipeline_stage_id))
    Pipelines::MoveEntryService.new(
      entry: @entry, stage: stage, user: Current.user, reason: params[:reason], loss_reason_id: params[:loss_reason_id],
      source: params[:source].presence_in(PipelineEntryEvent::SOURCES) || 'web'
    ).perform
    preload_latest_conversations([@entry])
    render :show
  end

  def destroy
    @entry.destroy!
    head :ok
  end

  def events
    @events = @entry.events.includes(:from_stage, :to_stage, :user, :loss_reason)
  end

  private

  def fetch_entry
    @entry = Current.account.pipeline_entries.find(params[:id])
  end
end
