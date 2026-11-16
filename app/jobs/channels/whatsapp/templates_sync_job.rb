class Channels::Whatsapp::TemplatesSyncJob < ApplicationJob
  queue_as :low

  def perform(whatsapp_channel)
    if whatsapp_channel.sync_templates
      whatsapp_channel.share_templates_with_siblings
    else
      # A channel Meta keeps refusing (bad token, removed number) waits for the
      # next window instead of being picked again on every scheduler run.
      whatsapp_channel.mark_message_templates_updated
    end
  end
end
