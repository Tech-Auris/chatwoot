# A failed Graph call that keeps Meta's error code, so a caller can tell a refused credential from
# any other failure (a 5xx, a rate limit, a permission error on this one request).
class Whatsapp::ApiError < StandardError
  attr_reader :http_status, :code, :subcode

  def initialize(message:, http_status:, code: nil, subcode: nil)
    super(message)
    @http_status = http_status
    @code = code
    @subcode = subcode
  end

  def self.from_response(response, message:)
    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
    error = {} unless error.is_a?(Hash)

    new(message: message, http_status: response.code, code: error['code'], subcode: error['error_subcode'])
  end

  # 190: the token was revoked or expired. 100/33: the token no longer sees the object (the WABA or
  # the number was dropped from it).
  def credentials_refused?
    code.to_i == 190 || (code.to_i == 100 && subcode.to_i == 33)
  end
end
