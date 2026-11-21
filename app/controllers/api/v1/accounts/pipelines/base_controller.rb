class Api::V1::Accounts::Pipelines::BaseController < Api::V1::Accounts::BaseController
  include PipelineEntriesLoader

  before_action :fetch_pipeline

  private

  def fetch_pipeline
    @pipeline = Current.account.pipelines.find(params[:pipeline_id])
  end
end
