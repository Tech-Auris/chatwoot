class MessageContentPresenter < SimpleDelegator
  def outgoing_content
    Messages::MarkdownRendererService.new(
      content_with_survey_link,
      conversation.inbox.channel_type,
      conversation.inbox.channel
    ).render
  end

  # WhatsApp Cloud delivers messages it cannot render as `type: unsupported`
  # with no real content, and we persist the localized "Esta mensagem não é
  # suportada..." placeholder so the operator UI has something to render.
  # That placeholder was leaking into every downstream webhook (n8n, AI
  # agents), where consumers took it for a real customer message. Sending
  # blank keeps the placeholder in the dashboard while signalling "no
  # content" to whoever reads the payload — the
  # `content_attributes.is_unsupported` flag on the same payload is what
  # a webhook consumer should branch on.
  def webhook_content
    return '' if content_attributes.is_a?(Hash) && content_attributes['is_unsupported']

    Messages::WebhookContentNormalizer.normalize(content_with_survey_link)
  end

  private

  def content_with_survey_link
    if should_append_survey_link?
      survey_link = survey_url(conversation.uuid)
      custom_message = inbox.csat_config&.dig('message')
      custom_message.present? ? "#{custom_message} #{survey_link}" : I18n.t('conversations.survey.response', link: survey_link)
    else
      content
    end
  end

  def should_append_survey_link?
    input_csat? && !inbox.web_widget?
  end

  def survey_url(conversation_uuid)
    "#{ENV.fetch('FRONTEND_URL', nil)}/survey/responses/#{conversation_uuid}"
  end
end
