# Shared by the reports of a clinic pipeline (Visão geral and Conversão):
# the pipeline, its entries and its history, narrowed by the label filter.
module V2::Reports::PipelineReportScope
  include DateRangeHelper

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  private

  def pipeline
    @pipeline ||= account.pipelines.find(params[:pipeline_id])
  end

  def stages
    @stages ||= pipeline.stages.to_a
  end

  def entries_scope
    scope = pipeline.entries
    scope = scope.where(contact_id: account.contacts.tagged_with(params[:label], any: true).select(:id)) if params[:label].present?
    scope
  end

  def events_scope
    scope = pipeline.entry_events
    scope = scope.where(pipeline_entry_id: entries_scope.select(:id)) if params[:label].present?
    scope
  end

  def events_in_range
    range.present? ? events_scope.where(created_at: range) : events_scope
  end

  def distinct_entries_by_stage(scope)
    scope.group(:to_stage_id).distinct.count(:pipeline_entry_id)
  end

  def rate(count, total)
    total.zero? ? 0 : ((count.to_f / total) * 100).round(2)
  end
end
