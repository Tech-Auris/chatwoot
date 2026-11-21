# Shared by the clinic pipeline endpoints that render entries: the card opens
# the contact's most recent conversation and shows whether it is open, so
# that conversation is loaded for every entry in one query.
module PipelineEntriesLoader
  extend ActiveSupport::Concern

  included do
    rescue_from CustomExceptions::Pipeline, with: :render_error_response
  end

  private

  def preload_latest_conversations(entries)
    contact_ids = entries.map(&:contact_id).uniq
    @latest_conversations = if contact_ids.empty?
                              {}
                            else
                              Current.account.conversations
                                     .where(contact_id: contact_ids)
                                     .select('DISTINCT ON (conversations.contact_id) conversations.id, conversations.display_id, ' \
                                             'conversations.status, conversations.contact_id')
                                     .order(:contact_id, last_activity_at: :desc)
                                     .index_by(&:contact_id)
                            end
  end
end
