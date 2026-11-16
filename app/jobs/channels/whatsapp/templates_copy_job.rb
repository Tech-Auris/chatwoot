# Gives a channel the template list another number on the same WABA just
# got from Meta, so every inbox of the WABA shows the same templates without
# a second call to Meta. Header media ids belong to each phone number, so
# they are resolved again for this channel.
class Channels::Whatsapp::TemplatesCopyJob < ApplicationJob
  queue_as :default

  def perform(channel, source)
    templates = Array(source.message_templates).select { |template| template.is_a?(Hash) }
                                               .map { |template| template.except('header_media_id', 'header_media_source_url') }
    channel.provider_service.store_templates(templates, synced_at: source.message_templates_last_updated)
  end
end
