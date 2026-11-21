# The clinic's own stages of a pipeline. Ganho / Perdido come with the
# pipeline and stay at the end (see PipelineStage).
class Api::V1::Accounts::Pipelines::StagesController < Api::V1::Accounts::Pipelines::BaseController
  before_action -> { authorize(@pipeline, :update?) }
  before_action :fetch_stage, only: [:update, :destroy]

  def create
    @stage = @pipeline.stages.create!(stage_params)
    render :show
  end

  def update
    @stage.update!(stage_params)
    render :show
  end

  # `move_to_stage_id` says where the contacts on the stage go.
  def destroy
    move_to_stage = @pipeline.stages.find_by(id: params[:move_to_stage_id])
    Pipelines::DestroyStageService.new(stage: @stage, move_to_stage: move_to_stage, user: Current.user).perform
    head :ok
  end

  # `ids`: the clinic's own stages in the new order.
  def reorder
    stages = @pipeline.stages.open.index_by(&:id)
    ActiveRecord::Base.transaction do
      Array(params.require(:ids)).each_with_index do |id, index|
        stages[id.to_i]&.update!(position: index)
      end
    end
    @stages = @pipeline.stages.reload
    render :index
  end

  private

  def fetch_stage
    @stage = @pipeline.stages.find(params[:id])
  end

  def stage_params
    params.permit(:name, :color)
  end
end
