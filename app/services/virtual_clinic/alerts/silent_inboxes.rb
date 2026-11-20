# Clara: an inbox she serves is disconnected (WhatsApp Baileys / Z-API), or
# connected but got no patient message for more than 2 hours while it
# usually does (the "deaf number" case).
class VirtualClinic::Alerts::SilentInboxes < VirtualClinic::Alerts::Rule
  SILENT_HOURS = 2

  def payload
    inboxes = account.inboxes.where(secretary_enabled: true).includes(:channel).filter_map { |inbox| problem(inbox) }
    return if inboxes.empty?

    { count: inboxes.size, names: inboxes.pluck(:name).join(', '), inboxes: inboxes }
  end

  private

  def problem(inbox)
    return { name: inbox.name, reason: 'disconnected' } if disconnected?(inbox.channel)

    last = Message.where(inbox_id: inbox.id, message_type: :incoming, created_at: 7.days.ago..).maximum(:created_at)
    return if last.nil? || last > SILENT_HOURS.hours.ago

    { name: inbox.name, reason: 'silent', hours: (minutes_since(last) / 60) }
  end

  def disconnected?(channel)
    channel.is_a?(Channel::Whatsapp) && %w[baileys zapi].include?(channel.provider) &&
      channel.provider_connection.present? && channel.provider_connection['connection'] != 'open'
  end
end
