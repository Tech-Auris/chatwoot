# Sets `Conversation.origem` on the first inbound message of a conversation
# whose origin has not been decided yet, using signals the incoming pipeline
# hands us. The rule set is deliberately conservative — we only assign a
# positive value when the signal is unambiguous; everything else stays null
# and shows as "Sem Origem" in the UI for the operator to fill in manually.
#
# Priority (first match wins):
#   1. Google  — a `gclid=` token in the first message body.
#   2. Inbox channel is `Channel::Instagram` → Instagram. The channel itself
#      is the placement here, stronger than a same-webhook Meta referral.
#   3. Inbox channel is `Channel::FacebookPage` → Facebook. Same reasoning.
#   4. Meta CTWA referral present (WhatsApp path — IG/FB already handled):
#      * `source_url` clearly Instagram (ig.me / instagram.com) → Instagram.
#      * Anything else → Facebook (Meta does not expose IG vs FB placement
#        reliably on CTWA; FB is the more common placement in practice, and
#        the operator can flip the dropdown to Instagram when they know).
#   5. None of the above → leave null (Sem Origem). "Orgânico" stays a
#      manual selection — we do not want to claim an organic attribution
#      for a conversation that might have come from an unmapped source.
#
# Manual selections through the dropdown always win: this service never
# overwrites an existing origem value on the conversation. First-touch is
# per-conversation now (no cross-conversation guard) so a contact who
# reengages later from a different source captures that source on the new
# conversation without touching the old one.
class Contacts::OriginAttributionService
  # Fixed vocabulary shown in the `Origem` dropdown — must stay in sync
  # with the frontend selector and both i18n files. Any edit here needs a
  # matching frontend + locale edit or the dropdown will orphan a value.
  OPTIONS = [
    'Evento',
    'Facebook',
    'Google',
    'Indicação de cliente',
    'Indicação de colega',
    'Influenciador',
    'Instagram',
    'Orgânico'
  ].freeze

  pattr_initialize [:inbox!, :conversation!, :message_body, :referral]

  def apply!
    return if conversation.origem.present?

    attributed = infer_origem
    return if attributed.nil?

    conversation.update!(origem: attributed)
  end

  private

  def infer_origem
    return 'Google' if gclid_present?
    return 'Instagram' if inbox.instagram_direct?
    return 'Facebook' if inbox.facebook?
    return referral_derived_origem if referral.present?

    nil
  end

  def gclid_present?
    ::CampaignReferralExtractor.gclid_from_body(message_body).present?
  end

  def referral_derived_origem
    source_url = referral['source_url'].to_s
    return 'Instagram' if source_url.match?(/(ig|instagram)\.com|ig\.me/i)

    'Facebook'
  end
end
