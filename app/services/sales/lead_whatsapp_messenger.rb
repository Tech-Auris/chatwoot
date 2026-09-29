# Sends a message to a proposal's lead on WhatsApp, through the inbox set in
# Commercial → Settings (the main seller's number). Works like the dashboard's
# new-conversation pencil: finds the contact by phone — with and without the
# Brazilian 9th digit, the usual source of duplicates — or creates it, reuses
# the open conversation of that inbox or opens one, and sends.
#
# The phone comes from the ClickUp deal at send time, so a number corrected
# there after the proposal was built is the one used; the proposal's copy is
# the fallback when ClickUp can't be reached.
class Sales::LeadWhatsappMessenger
  class NotConfigured < StandardError; end
  class MissingPhone < StandardError; end

  DEFAULT_ACCOUNT_ID = 1
  DEFAULT_INBOX_ID = 385

  pattr_initialize [:quote!, :content!]

  def self.account_id
    (GlobalConfigService.load('COMMERCIAL_WHATSAPP_ACCOUNT_ID', nil).presence || DEFAULT_ACCOUNT_ID).to_i
  end

  def self.inbox_id
    (GlobalConfigService.load('COMMERCIAL_WHATSAPP_INBOX_ID', nil).presence || DEFAULT_INBOX_ID).to_i
  end

  def perform
    contact = find_or_create_contact
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: nil).perform
    conversation = open_conversation(contact_inbox)
    Messages::MessageBuilder.new(nil, conversation, { content: content, message_type: 'outgoing' }).perform
    conversation
  end

  private

  def inbox
    @inbox ||= Account.find_by(id: self.class.account_id)&.inboxes&.find_by(id: self.class.inbox_id) ||
               raise(NotConfigured, 'Configure a conta e a caixa em Commercial → Settings')
  end

  def phone
    @phone ||= begin
      digits = (clickup_phone.presence || quote.prospect_phone).to_s.gsub(/\D/, '')
      raise MissingPhone, 'O lead não tem telefone no ClickUp nem na proposta' if digits.blank?

      digits = "55#{digits}" if [10, 11].include?(digits.length)
      digits
    end
  end

  def clickup_phone
    Sales::ClickupProspectSearchService.new.find(quote.clickup_task_id)&.dig(:phone)
  rescue StandardError => e
    Rails.logger.warn("[Sales::LeadWhatsappMessenger] ClickUp phone lookup failed for quote #{quote.id}: #{e.message}")
    nil
  end

  # 55 + DDD + 9 digits ⇄ 55 + DDD + 8 digits: the same Brazilian mobile
  # written before and after the 9th digit.
  def phone_variants
    variants = [phone]
    if phone.start_with?('55') && phone.length == 13 && phone[4] == '9'
      variants << (phone[0, 4] + phone[5..])
    elsif phone.start_with?('55') && phone.length == 12
      variants << "#{phone[0, 4]}9#{phone[4..]}"
    end
    variants
  end

  def find_or_create_contact
    by_inbox = inbox.contact_inboxes.find_by(source_id: phone_variants)&.contact
    return by_inbox if by_inbox

    inbox.account.contacts.find_by(phone_number: phone_variants.map { |digits| "+#{digits}" }) ||
      inbox.account.contacts.create!(name: quote.prospect_name.presence || "+#{phone}", phone_number: "+#{phone}")
  end

  def open_conversation(contact_inbox)
    contact_inbox.conversations.where.not(status: :resolved).order(:created_at).last ||
      ConversationBuilder.new(params: ActionController::Parameters.new({}), contact_inbox: contact_inbox).perform
  end
end
