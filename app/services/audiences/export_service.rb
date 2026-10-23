require 'csv'

# The CSV of an audience's contacts ("Baixar lista"), with the columns the
# user picked. The stage, loss reason, labels, inbox, origin, origin date,
# agent and conversation number come from each contact's latest conversation.
# Read in batches, with the BOM spreadsheet apps need for accented names.
class Audiences::ExportService
  COLUMNS = %w[name phone_number email funnel_stage loss_reason labels inbox origem origin_date assignee conversation_id].freeze
  BATCH_SIZE = 500
  BOM = "\xEF\xBB\xBF".freeze

  pattr_initialize [:audience!, :columns]

  def perform
    "#{BOM}#{csv}"
  end

  def selected_columns
    picked = Array(columns) & COLUMNS
    picked.presence || COLUMNS
  end

  def filename
    "#{audience.name.parameterize.presence || 'publico'}-#{Time.zone.today}.csv"
  end

  private

  def csv
    CSV.generate do |output|
      output << selected_columns.map { |column| I18n.t("audiences.export.columns.#{column}") }
      audience.contacts.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        conversations = latest_conversations(batch.map(&:id))
        batch.each { |contact| output << row_for(contact, conversations[contact.id]) }
      end
    end
  end

  def row_for(contact, conversation)
    values = { 'name' => contact.name, 'phone_number' => contact.phone_number, 'email' => contact.email }
    values.merge!(conversation_values(conversation)) if conversation
    selected_columns.map { |column| values[column] }
  end

  def conversation_values(conversation)
    {
      'funnel_stage' => conversation.funnel_stage&.name, 'loss_reason' => conversation.loss_reason&.name,
      'labels' => conversation.cached_label_list_array.join(', '), 'inbox' => conversation.inbox&.name,
      'origem' => conversation.origem, 'origin_date' => conversation.created_at.in_time_zone.strftime('%d/%m/%Y'),
      'assignee' => conversation.assignee&.name, 'conversation_id' => conversation.display_id
    }
  end

  def latest_conversations(contact_ids)
    audience.account.conversations.where(contact_id: contact_ids)
            .select('DISTINCT ON (conversations.contact_id) conversations.*')
            .reorder(Arel.sql('conversations.contact_id, conversations.created_at DESC'))
            .includes(:inbox, :funnel_stage, :loss_reason, :assignee).index_by(&:contact_id)
  end
end
