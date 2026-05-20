# One-off cleanup for contacts created during Baileys history-import runs that
# happened BEFORE the node-side enrichment was deployed (v3.1.2-auris.1.1).
# Those imports could not stamp `pushName` on history messages, so the Rails
# `set_contact` fallback came up blank and `ContactInboxWithContactBuilder`
# generated a Haikunator name (e.g. "little-leaf-699"). New imports already
# bring proper names; this task renames the existing rows so the operator sees
# something meaningful instead of the random adjective-noun-number.
#
# Scope: Baileys-provider WhatsApp inboxes only, contacts whose `name` matches
# the Haikunator pattern `<word>-<word>-<digits>` AND whose `identifier` ends
# with `@lid` (which guarantees the contact was created by the Baileys flow,
# not by a coincidentally-named webchat visitor).
#
# Rename policy:
# - If the contact has a `phone_number`, the new name is the phone digits
#   (without the leading `+`).
# - Otherwise, the new name is the LID id (the part before `@lid` in the
#   identifier).
#
# Usage:
#   # Dry-run (default): print what would change, change nothing.
#   bundle exec rake baileys:cleanup_haikunator_history_contacts
#   bundle exec rake baileys:cleanup_haikunator_history_contacts ACCOUNT_ID=1
#   bundle exec rake baileys:cleanup_haikunator_history_contacts INBOX_ID=42
#
#   # Apply the rename:
#   bundle exec rake baileys:cleanup_haikunator_history_contacts APPLY=1

# rubocop:disable Metrics/BlockLength
namespace :baileys do
  desc 'Rename Haikunator-named contacts created by Baileys history imports'
  task cleanup_haikunator_history_contacts: :environment do
    apply = ENV['APPLY'].present?
    account_id = ENV['ACCOUNT_ID'].presence&.to_i
    inbox_id = ENV['INBOX_ID'].presence&.to_i

    inbox_scope = Inbox.joins(:channel_whatsapp)
                       .where(channel_whatsapp: { provider: 'baileys' })
    inbox_scope = inbox_scope.where(account_id: account_id) if account_id
    inbox_scope = inbox_scope.where(id: inbox_id) if inbox_id

    inbox_ids = inbox_scope.pluck(:id)
    if inbox_ids.empty?
      puts 'No Baileys WhatsApp inboxes matched the filter; nothing to do.'
      next
    end

    contact_ids = ContactInbox.where(inbox_id: inbox_ids).distinct.pluck(:contact_id)
    contacts = Contact.where(id: contact_ids)
                      .where('name ~ ?', '^[a-z]+-[a-z]+-[0-9]+$')
                      .where('identifier LIKE ?', '%@lid')

    total = contacts.count
    puts "Scanning #{total} haikunator-named contacts across #{inbox_ids.size} Baileys inbox(es)."
    puts "Mode: #{apply ? 'APPLY (writes will happen)' : 'DRY-RUN (no changes)'}"

    renamed = 0
    skipped = 0

    contacts.find_each do |contact|
      new_name = next_name_for(contact)
      if new_name.blank? || new_name == contact.name
        skipped += 1
        next
      end

      puts(
        "  #{contact.id}: #{contact.name.inspect} -> #{new_name.inspect}",
        "    (phone=#{contact.phone_number.inspect} identifier=#{contact.identifier.inspect})"
      )
      contact.update!(name: new_name) if apply
      renamed += 1
    end

    puts ''
    puts "Done. would_rename=#{renamed} skipped=#{skipped} mode=#{apply ? 'APPLY' : 'DRY-RUN'}"
  end

  # Phone wins because it's the canonical user-facing identifier; LID is an
  # opaque routing id but still better than a random English adjective-noun.
  def self.next_name_for(contact)
    return contact.phone_number.to_s.delete('+') if contact.phone_number.present?
    return nil if contact.identifier.blank?

    lid = contact.identifier.split('@').first
    lid.presence
  end
end
# rubocop:enable Metrics/BlockLength
