require 'csv'

# Builds the contacts CSV.
#
# Shared by the e-mail export job and by the direct download, so both produce
# byte-identical files — a divergence here would show up as "the download has
# different columns than the e-mail", which nobody would think to check.
#
# Contacts are read in batches: an account with tens of thousands of them would
# otherwise be loaded into memory all at once, and this now runs inside a web
# request as well as in a job.
class Contacts::ExportService
  BATCH_SIZE = 500
  LABELS_COLUMN = 'labels'.freeze
  LABELS_DELIMITER = ','.freeze
  DEFAULT_COLUMNS = %w[id name email phone_number labels].freeze
  # Spreadsheet applications need the BOM to read non-ASCII names correctly.
  BOM = "\xEF\xBB\xBF".freeze

  pattr_initialize [:account!, :user!, :column_names, :params]

  def perform
    headers = valid_headers

    csv = CSV.generate do |output|
      output << headers
      each_batch do |batch|
        labels = headers.include?(LABELS_COLUMN) ? labels_for(batch) : {}
        batch.each { |contact| output << headers.map { |header| value_for(contact, header, labels) } }
      end
    end

    "#{BOM}#{csv}"
  end

  def filename
    "#{account.name}_#{account.id}_contacts.csv"
  end

  private

  def each_batch(&)
    scope = contacts
    return scope.find_in_batches(batch_size: BATCH_SIZE, &) if scope.respond_to?(:find_in_batches)

    scope.each_slice(BATCH_SIZE, &)
  end

  def value_for(contact, header, labels)
    return labels.fetch(contact.id, []).join(LABELS_DELIMITER) if header == LABELS_COLUMN

    contact.send(header)
  end

  # Only labels the account actually declares are exported, so a stray tag
  # cannot leak into the file.
  def approved_labels
    @approved_labels ||= account.labels.pluck(:title)
  end

  def labels_for(batch)
    contact_ids = batch.map(&:id)
    return {} if contact_ids.blank?

    ActsAsTaggableOn::Tagging
      .joins(:tag)
      .where(context: LABELS_COLUMN, taggable_type: 'Contact', taggable_id: contact_ids)
      .where(tags: { name: approved_labels })
      .pluck(:taggable_id, 'tags.name')
      .each_with_object(Hash.new { |hash, id| hash[id] = [] }) { |(contact_id, label), acc| acc[contact_id] << label }
  end

  def contacts
    filter_params = params || {}

    if filter_params[:payload].present? && filter_params[:payload].any?
      ::Contacts::FilterService.new(account, user, filter_params).perform[:contacts]
    elsif filter_params[:label].present?
      resolved_contacts.tagged_with(filter_params[:label], any: true)
    else
      resolved_contacts
    end
  end

  def resolved_contacts
    account.contacts.resolved_contacts(use_crm_v2: account.feature_enabled?('crm_v2'))
  end

  def valid_headers
    requested = column_names.presence || DEFAULT_COLUMNS

    # Keep the requested order while allowing the virtual labels column.
    requested.select { |header| header == LABELS_COLUMN || Contact.column_names.include?(header) }.uniq
  end
end
