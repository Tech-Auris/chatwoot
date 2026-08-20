require 'csv'

# Reads the monthly token-usage spreadsheet the finance team already exports.
#
# Header names come from that export ("accountid", "imagem arquivo e
# transcrições"), so matching is done on a normalized form — accents, spaces,
# underscores and case all vary between exports and none of them should make an
# operator edit the file by hand before importing.
class Financial::TokenUsageCsvParser
  class InvalidFile < StandardError; end

  MAX_ROWS = 2_000

  # Every spelling of a column we accept, normalized. First match wins.
  COLUMN_ALIASES = {
    account_id: %w[accountid accountid# account_id conta id idconta],
    account_name: %w[accountname account_name conta nome nomeconta],
    text: %w[texto textos mensagensdetexto text],
    media: %w[imagemarquivoetranscricoes imagem midia media arquivos transcricoes],
    audio: %w[audio audios mensagensdeaudio]
  }.freeze

  REQUIRED = %i[account_id text media audio].freeze

  pattr_initialize [:file!]

  def parse
    table = read_table
    mapping = column_mapping(table.headers)
    missing = REQUIRED.reject { |key| mapping.key?(key) }
    raise InvalidFile, "Colunas obrigatórias ausentes: #{missing.join(', ')}" if missing.any?

    rows = table.filter_map { |row| build_row(row, mapping) }
    raise InvalidFile, "O arquivo tem mais de #{MAX_ROWS} linhas" if rows.size > MAX_ROWS

    rows
  end

  private

  def read_table
    CSV.parse(content, headers: true, col_sep: separator)
  rescue CSV::MalformedCSVError => e
    raise InvalidFile, "Arquivo inválido: #{e.message}"
  end

  def content
    @content ||= file.read.to_s.force_encoding('UTF-8').sub("\xEF\xBB\xBF", '')
  end

  # Brazilian spreadsheets export with semicolons as often as with commas.
  def separator
    header = content.lines.first.to_s
    header.count(';') > header.count(',') ? ';' : ','
  end

  def column_mapping(headers)
    headers.compact.each_with_object({}) do |header, mapping|
      key = COLUMN_ALIASES.find { |_, aliases| aliases.include?(normalize(header)) }&.first
      mapping[key] ||= header if key
    end
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z0-9]/, '')
  end

  def build_row(row, mapping)
    account_id = to_integer(row[mapping[:account_id]])
    return if account_id.zero?

    {
      account_id: account_id,
      account_name: mapping[:account_name] ? row[mapping[:account_name]] : nil,
      text: to_integer(row[mapping[:text]]),
      media: to_integer(row[mapping[:media]]),
      audio: to_integer(row[mapping[:audio]])
    }
  end

  # Quantities arrive formatted for humans ("1.480", "1 480"), which `to_i`
  # would read as 1 — every non-digit goes before converting.
  def to_integer(value)
    value.to_s.gsub(/\D/, '').to_i
  end
end
