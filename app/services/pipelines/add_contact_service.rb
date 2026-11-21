# Puts a contact in a clinic pipeline, on the given stage or on the first one.
# Idempotent: a contact already in progress in the pipeline keeps the entry it
# has. A contact whose last pass ended (Ganho / Perdido) enters again.
class Pipelines::AddContactService
  include Events::Types

  pattr_initialize [:pipeline!, :contact!, { stage: nil, user: nil, source: :manual, origin: nil, event_source: 'web' }]

  def perform
    raise CustomExceptions::Pipeline.new(key: :archived) if pipeline.archived?

    existing_entry || create_entry!
  rescue ActiveRecord::RecordNotUnique
    existing_entry
  end

  private

  def existing_entry
    pipeline.entries.open_entries.find_by(contact_id: contact.id)
  end

  def create_entry!
    validate_stage!
    entry = ActiveRecord::Base.transaction do
      pipeline.entries.create!(entry_attributes).tap do |created|
        created.events.create!(pipeline: pipeline, to_stage: target_stage, user: user, source: event_source)
      end
    end
    Rails.configuration.dispatcher.dispatch(PIPELINE_ENTRY_UPDATED, Time.zone.now, entry: entry, previous_stage: nil,
                                                                                   new_stage: target_stage, user: user)
    entry
  end

  def entry_attributes
    { account: pipeline.account, contact: contact, stage: target_stage, stage_entered_at: Time.current,
      source: source, added_by: user, origin: origin }
  end

  def target_stage
    @target_stage ||= stage || pipeline.first_open_stage
  end

  def validate_stage!
    return if target_stage&.pipeline_id == pipeline.id && target_stage.open?

    raise CustomExceptions::Pipeline.new(key: :stage_mismatch)
  end
end
