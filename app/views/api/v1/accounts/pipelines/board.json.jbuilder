json.payload do
  json.stages @stages do |stage|
    entries = @entries_by_stage[stage] || []
    total = @stage_totals[stage.id] || 0
    json.partial! 'api/v1/accounts/pipelines/stages/stage', formats: [:json], stage: stage
    json.entries entries do |entry|
      json.partial! 'api/v1/accounts/pipeline_entries/entry', formats: [:json], entry: entry
    end
    json.count total
    json.has_more entries.size < total
  end
end
