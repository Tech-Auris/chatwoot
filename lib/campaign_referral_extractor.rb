# Extracts campaign-attribution signals from an inbound WhatsApp message so the
# rest of the app can persist and render them. Two shapes it knows about:
#
# * Meta Cloud API's `referral` object — populated when the conversation was
#   opened from a Click-to-WhatsApp Ad. Carries the ad's headline/body/image
#   plus the `ctwa_clid` we need later to close the CAPI loop.
# * A `gclid=<token>` fragment inside the message body — how the site snippet
#   forwards a Google Ads click into the prefilled WhatsApp text.
#
# The referral output is normalized to a provider-agnostic shape (`title`,
# `body`, `source_url`, `thumbnail_url`, ...) so the frontend renders the same
# card regardless of whether the payload came from Cloud (`headline` /
# `image_url`) or Baileys (`title` / `thumbnailUrl` — Baileys wiring lives
# elsewhere; this module owns the Cloud side).
#
# Baileys does not emit either signal through Cloud webhooks; a nil result from
# these helpers is the expected shape there.
module CampaignReferralExtractor
  module_function

  GCLID_PATTERN = /gclid=([\w-]+)/i

  # Returns a normalized hash for the message's Meta referral, or nil if there
  # is nothing usable (missing referral, or every field blank).
  def from_cloud_message(message)
    raw = referral_from(message)
    return nil if raw.blank?

    ref = raw.with_indifferent_access
    {
      'source_type' => ref[:source_type],
      'source_id' => ref[:source_id],
      'source_url' => ref[:source_url],
      'ctwa_clid' => ref[:ctwa_clid],
      'title' => ref[:headline],
      'body' => ref[:body],
      'media_type' => ref[:media_type].to_s.downcase.presence,
      'thumbnail_url' => ref[:image_url] || ref[:thumbnail_url] || ref[:video_url]
    }.compact_blank.presence
  end

  # Returns the raw GCLID token found in the body, or nil.
  def gclid_from_body(body)
    return nil if body.blank?

    match = body.to_s.match(GCLID_PATTERN)
    match && match[1]
  end

  def referral_from(message)
    return nil unless message.is_a?(Hash)

    message[:referral] || message['referral']
  end
  private_class_method :referral_from
end
