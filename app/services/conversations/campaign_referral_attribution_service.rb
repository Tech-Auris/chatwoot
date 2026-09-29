# Records which ad / campaign brought a lead on a conversation that already
# exists, for leads that reach us outside the messaging channel's own
# referral capture — typically a website form (respondi.app, Typeform…)
# relayed by n8n, whose conversation may have been opened earlier.
#
# First touch wins, same as the click-to-WhatsApp capture: a conversation that
# already carries a `campaign_referral` keeps it, so a lead re-submitting the
# form (or who first came from a CTWA ad) is not re-credited to a later ad.
#
# Only the keys the reports and the conversion dispatchers read are kept:
#   * source_id     — the ad id; joins the funnel's "Anúncios do período" grid
#                     and the ad spend synced from Meta
#   * title         — ad name shown on the grid and the origin card
#   * fbclid/gclid  — click ids the Meta CAPI / Google Ads dispatchers send back
#   * captured_at   — unix time of the submission (Meta's fbc creation time)
class Conversations::CampaignReferralAttributionService
  ALLOWED_KEYS = %w[
    source_type source_id source_url title body campaign_name
    utm_source utm_medium utm_campaign utm_term utm_content
    fbclid gclid captured_at
  ].freeze

  pattr_initialize [:conversation!, :referral!]

  # Returns true when the referral was recorded, false when the conversation
  # already had one (or nothing usable was sent).
  def perform
    return false if conversation.additional_attributes.to_h['campaign_referral'].present?

    attributes = normalized_referral
    return false if attributes.empty?

    conversation.update!(additional_attributes: conversation.additional_attributes.to_h.merge('campaign_referral' => attributes))
    true
  end

  private

  def normalized_referral
    attributes = referral.to_h.stringify_keys.slice(*ALLOWED_KEYS).transform_values { |value| value.to_s.strip }.compact_blank
    attributes['captured_at'] = attributes['captured_at'].to_i if attributes['captured_at'].present?
    attributes
  end
end
