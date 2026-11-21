# The clinic pipelines of a contact — for "Adicionar a", the "Funis (N)"
# button of the conversation header and the Funis block of the contact panel.
# One entry per pipeline: the one in progress, or else the latest pass.
class Api::V1::Accounts::Contacts::PipelineEntriesController < Api::V1::Accounts::Contacts::BaseController
  include PipelineEntriesLoader

  def index
    authorize PipelineEntry, :index?
    @entries = @contact.pipeline_entries
                       .joins(:pipeline).merge(Pipeline.active)
                       .includes(:pipeline, :stage, :added_by, :loss_reason, contact: { avatar_attachment: :blob })
                       .order(Arel.sql('pipeline_entries.closed_at IS NULL DESC'), created_at: :desc)
                       .uniq(&:pipeline_id)
    preload_latest_conversations(@entries)
    render 'api/v1/accounts/pipeline_entries/index'
  end
end
