# Revokes a message on the provider after the agent deleted it.
#
# Two mutually exclusive triggers (both take the message row lock): the DELETE endpoint, when the
# message already has a `source_id`, and `Whatsapp::SendOnWhatsappService`, when the message got
# deleted while the send was in flight and the `source_id` only landed afterwards. Retries so a
# provider hiccup doesn't leave the message deleted here and alive on WhatsApp.
class Messages::DeleteOnChannelJob < ApplicationJob
  queue_as :high

  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
    Rails.logger.error "Failed to delete message #{job.arguments.first} on channel: #{error.message}"
  end

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank? || message.source_id.blank?

    channel = message.inbox.channel
    return unless channel.respond_to?(:delete_message)

    channel.delete_message(message, conversation: message.conversation)
  end
end
