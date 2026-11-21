# "Adicionar a": puts a contact in the pipeline (first stage unless
# `pipeline_stage_id` says otherwise). Adding a contact already in progress
# returns the entry it has.
class Api::V1::Accounts::Pipelines::EntriesController < Api::V1::Accounts::Pipelines::BaseController
  def create
    authorize PipelineEntry, :create?
    contact = Current.account.contacts.find(params.require(:contact_id))
    stage = @pipeline.stages.find(params[:pipeline_stage_id]) if params[:pipeline_stage_id].present?
    @entry = Pipelines::AddContactService.new(
      pipeline: @pipeline, contact: contact, stage: stage, user: Current.user, source: :manual,
      event_source: params[:source].presence_in(PipelineEntryEvent::SOURCES) || 'web'
    ).perform
    preload_latest_conversations([@entry])
    render 'api/v1/accounts/pipeline_entries/show'
  end
end
