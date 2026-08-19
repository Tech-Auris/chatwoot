require 'csv'

# Turns an uploaded CSV into the contacts a campaign will target.
#
# The phone number is the identity key: a row whose number already exists in
# the account reuses that contact instead of creating a duplicate, so running
# the same file twice doesn't fan the audience out.
#
# Nothing here is persisted onto the campaign — the caller receives the contact
# ids and stores them as the campaign audience, which keeps the file a
# one-time input rather than state we have to keep in sync.
class Campaigns::AudienceCsvImportService
  REQUIRED_HEADERS = %w[name phone_number].freeze
  MAX_ROWS = 5_000

  class InvalidFile < StandardError; end

  pattr_initialize [:account!, :file!]

  def perform
    rows = parse_rows
    raise InvalidFile, "O arquivo tem mais de #{MAX_ROWS} linhas" if rows.size > MAX_ROWS

    result = { contact_ids: [], created_count: 0, reused_count: 0, invalid_rows: [] }
    rows.each_with_index { |row, index| process_row(row, index + 2, result) }
    result
  end

  private

  def parse_rows
    table = CSV.parse(file.read.force_encoding('UTF-8'), headers: true, header_converters: :downcase)
    missing = REQUIRED_HEADERS - table.headers.compact.map(&:to_s)
    raise InvalidFile, "Colunas obrigatórias ausentes: #{missing.join(', ')}" if missing.any?

    table
  rescue CSV::MalformedCSVError => e
    raise InvalidFile, "Arquivo CSV inválido: #{e.message}"
  end

  def process_row(row, line, result)
    phone = normalize_phone(row['phone_number'])
    return result[:invalid_rows] << { line: line, reason: 'telefone ausente ou inválido' } if phone.blank?

    contact = account.contacts.find_by(phone_number: phone)
    if contact
      fill_gaps(contact, row, phone)
      result[:reused_count] += 1
    else
      contact = create_contact(row, phone)
      return result[:invalid_rows] << { line: line, reason: contact.errors.full_messages.to_sentence } unless contact.persisted?

      result[:created_count] += 1
    end

    result[:contact_ids] << contact.id
  end

  # A contact created from an inbound message usually carries the number as its
  # name, and often has no email. The spreadsheet fills those gaps — but never
  # overwrites a real name or an existing email, which would let a campaign
  # list degrade data the team curated.
  def fill_gaps(contact, row, phone)
    attributes = {}
    attributes[:name] = row['name'] if row['name'].present? && placeholder_name?(contact, phone)
    attributes[:email] = row['email'] if row['email'].present? && contact.email.blank?
    return if attributes.empty?

    return if contact.update(attributes)

    Rails.logger.info "[campaign audience] could not enrich contact #{contact.id}: #{contact.errors.full_messages.to_sentence}"
  end

  def placeholder_name?(contact, phone)
    contact.name.blank? || contact.name.gsub(/\D/, '') == phone.gsub(/\D/, '')
  end

  def create_contact(row, phone)
    account.contacts.create(
      name: row['name'].presence || phone,
      email: row['email'].presence,
      phone_number: phone
    )
  end

  # Contacts are stored in E.164. Spreadsheets hand us numbers with spaces,
  # dashes and parentheses, and often without the plus sign.
  def normalize_phone(value)
    digits = value.to_s.gsub(/\D/, '')
    return nil if digits.length < 8

    "+#{digits}"
  end
end
