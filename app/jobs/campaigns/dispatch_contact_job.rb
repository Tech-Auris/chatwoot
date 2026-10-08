# One contact of a one-off WhatsApp campaign: its conversation, label and
# message. The campaign schedules one of these per contact, `cadence_seconds`
# apart, so that work is spread over the campaign instead of landing all at
# once when it starts (a 232-contact list used to create every conversation
# and message in the same minute).
class Campaigns::DispatchContactJob < ApplicationJob
  queue_as :campaign

  def perform(campaign_id, contact_id)
    campaign = Campaign.find_by(id: campaign_id)
    contact = campaign&.account&.contacts&.find_by(id: contact_id)
    return if contact.nil?

    Whatsapp::OneoffCampaignService.new(campaign: campaign).dispatch_contact(contact)
  end
end
