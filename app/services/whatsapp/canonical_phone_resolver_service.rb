# For Brazilian numbers, the WhatsApp account may be registered under the
# pre-2012 12-digit format (no "9" after the area code) even when the line
# itself is the modern 13-digit form, and vice versa. Operators don't
# always know which one a given patient uses when they create the contact
# through the pencil flow.
#
# This service asks the Baileys provider which JID the WhatsApp servers
# actually associate with the number (via on_whatsapp). The canonical
# phone returned is the one that should be persisted on the contact and
# used as the contact_inbox source_id — eliminating the duplicate created
# later when the patient replies in the alternate format.
#
# `resolve` returns the input phone unchanged when:
#   - the channel isn't a Baileys WhatsApp channel
#   - the phone isn't a Brazilian one (other countries don't need this)
#   - on_whatsapp fails or both candidates report exists=false
#
# `lookup` tells those cases apart, because "no WhatsApp" and "could not
# ask" mean different things to the agent:
#   - Answer(exists: true, phone: <canonical digits>)
#   - Answer(exists: false) only when every probed form said no
#   - nil when nobody answered (lookup failed, inbox down, not applicable)
class Whatsapp::CanonicalPhoneResolverService
  BRAZILIAN_PHONE_REGEX = /\A55\d{10,11}\z/
  BRAZILIAN_13D_REGEX = /\A55\d{2}9\d{8}\z/

  Answer = Struct.new(:exists, :phone, keyword_init: true)

  def initialize(channel:, phone:)
    @channel = channel
    @phone = phone.to_s.delete('+')
  end

  def resolve
    answer = lookup
    answer&.exists ? answer.phone : @phone
  end

  def lookup
    return unless baileys_channel? && brazilian_phone?

    lookup_canonical_jid
  rescue StandardError => e
    Rails.logger.warn("[canonical-phone] resolve failed for #{@phone}: #{e.message}")
    nil
  end

  private

  # Ask WhatsApp directly which JID it associates with the (normalized)
  # number. baileys-api returns `exists: true` for the alternate BR format
  # too — the 13d input for a 12d-registered account still comes back as
  # existing — but the `jid` field always carries the canonical form the
  # server actually routes under. Trust that, not the input format.
  #
  # Fallback: try the 12d alternate — some accounts register only under
  # the legacy short form and the normalized 13d probe reports
  # `exists: false`. Same idea, the response's `jid` wins. Any probe that
  # raises makes the whole answer unknown (rescued in `lookup`).
  def lookup_canonical_jid
    normalized = Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize(@phone) || @phone
    [normalized, strip_brazilian_9(normalized)].compact.each do |candidate|
      server_jid = registered_jid_for(candidate)
      return Answer.new(exists: true, phone: server_jid) if server_jid.present?
    end
    Answer.new(exists: false)
  end

  def baileys_channel?
    @channel.is_a?(Channel::Whatsapp) && @channel.provider == 'baileys'
  end

  def brazilian_phone?
    @phone.match?(BRAZILIAN_PHONE_REGEX)
  end

  def strip_brazilian_9(phone)
    return nil unless phone.match?(BRAZILIAN_13D_REGEX)

    "#{phone[0, 4]}#{phone[5..]}"
  end

  # Returns the digit-only body of the JID WhatsApp reports for this phone
  # (canonical routing form), or nil when the number isn't registered.
  # Anything but a Hash is no answer at all, not a "no".
  def registered_jid_for(phone)
    response = @channel.on_whatsapp("#{phone}@s.whatsapp.net")
    raise ArgumentError, "unexpected on_whatsapp response: #{response.inspect}" unless response.is_a?(Hash)

    jid = response['exists'] == true ? response['jid'].to_s : nil
    return nil if jid.blank?

    jid.split('@').first
  end
end
