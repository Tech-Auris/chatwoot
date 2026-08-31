# Puts the agreed total inside the company's PIX code.
#
# The configured code is the account's static one and carries no amount, so the
# customer would have to type it — and a customer typing the total of a
# proposal they read minutes ago is a wrong transfer waiting to happen. The
# amount is a field of the code itself (BR Code, EMV®QRCPS): adding it means
# rebuilding the string with the field in its place and recomputing the
# checksum that closes it.
class Sales::PixCodeService
  AMOUNT_ID = '54'.freeze
  CRC_ID = '63'.freeze

  def initialize(payload:, amount_cents: nil)
    @payload = payload.to_s.strip
    @amount_cents = amount_cents.to_i
  end

  def perform
    return payload if payload.blank? || amount_cents <= 0

    # The old amount and the old checksum both go; the fields are written back
    # in ascending id order, which is how a reader expects to walk them.
    fields = parse(payload).except(AMOUNT_ID, CRC_ID)
                           .merge(AMOUNT_ID => format('%.2f', amount_cents / 100.0))

    with_checksum(fields.sort.map { |id, value| encode(id, value) }.join)
  rescue InvalidPayload
    # A code we cannot take apart is still a code the customer can pay by
    # typing the amount, which is what the page said before this existed.
    payload
  end

  private

  class InvalidPayload < StandardError; end

  attr_reader :payload, :amount_cents

  # Every field is id (2) + length (2) + value, one after the other.
  def parse(code)
    fields = {}
    cursor = 0

    while cursor < code.length
      id = code[cursor, 2]
      length = code[cursor + 2, 2].to_i
      value = code[cursor + 4, length].to_s
      raise InvalidPayload if id.blank? || length.zero? || value.length != length

      fields[id] = value
      cursor += 4 + length
    end

    fields
  end

  def encode(id, value)
    "#{id}#{format('%02d', value.length)}#{value}"
  end

  # The checksum covers everything up to and including its own id and length.
  def with_checksum(code)
    body = "#{code}#{CRC_ID}04"
    "#{body}#{crc16(body)}"
  end

  def crc16(body)
    crc = 0xFFFF

    body.each_byte do |byte|
      crc ^= byte << 8
      8.times { crc = crc.anybits?(0x8000) ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF }
    end

    format('%04X', crc)
  end
end
