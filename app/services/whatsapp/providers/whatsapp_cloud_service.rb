class Whatsapp::Providers::WhatsappCloudService < Whatsapp::Providers::BaseService # rubocop:disable Metrics/ClassLength
  def send_message(phone_number, message)
    @message = message

    if message.attachments.present?
      send_attachment_message(phone_number, message)
    elsif message.content_type == 'input_select'
      send_interactive_text_message(phone_number, message)
    elsif message.content_attributes[:is_reaction]
      send_reaction_message(phone_number, message)
    else
      send_text_message(phone_number, message)
    end
  end

  def send_template(phone_number, template_info, message)
    template_body = template_body_parameters(template_info)

    request_body = {
      messaging_product: 'whatsapp',
      recipient_type: 'individual', # Only individual messages supported (not group messages)
      to: phone_number,
      type: 'template',
      template: template_body
    }

    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: request_body.to_json
    )

    process_response(response, message)
  end

  def sync_templates
    # ensuring that channels with wrong provider config wouldn't keep trying to sync templates
    whatsapp_channel.mark_message_templates_updated
    templates = fetch_whatsapp_templates("#{business_account_path}/message_templates?access_token=#{whatsapp_channel.provider_config['api_key']}")
    whatsapp_channel.update!(message_templates: templates, message_templates_last_updated: Time.now.utc) if templates.present?
  end

  # Updates an existing template on Meta. Only certain fields are
  # editable and the rules depend on the template's current status
  # (body/header/footer/buttons trigger reapproval; name/language/category
  # are usually immutable). We forward whatever Meta receives and let it
  # decide — surfacing the rejection message when it refuses is more
  # honest than trying to mirror Meta's status→field matrix in the UI.
  def update_template(template_id, payload)
    response = HTTParty.post(
      "#{api_base_path}/v22.0/#{template_id}",
      headers: api_headers,
      body: payload.to_json
    )

    if response.success?
      { success: true, template: response.parsed_response }
    else
      Rails.logger.error "Meta template update failed: #{response.code} - #{response.body}"
      error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
      {
        success: false,
        error_code: error&.dig('code'),
        error_message: error&.dig('message') || response.body,
        error_details: error&.dig('error_user_msg') || error&.dig('error_data', 'details')
      }
    end
  end

  # Deletes a template from Meta. When we know the template id we pass
  # it as `hsm_id` alongside the name — Meta treats that as a surgical
  # single-language-variant delete, which several tokens accept even when
  # the name-only broad delete fails with #100 "Need permission on either
  # WhatsApp Business Account or owner/shared business". Falling back to
  # name-only preserves the old behavior for callers that don't have the
  # id handy. Returns a normalised hash so the controller does not need
  # to parse HTTP responses. Meta sometimes rejects deletion (template
  # in use by an active campaign, permission gaps) — those show up as
  # `success: false` with the original Meta error text so the operator
  # sees exactly what happened.
  def delete_template(template_name, template_id: nil)
    query = "name=#{CGI.escape(template_name)}"
    query = "#{query}&hsm_id=#{CGI.escape(template_id.to_s)}" if template_id.present?
    response = HTTParty.delete(
      "#{business_account_path}/message_templates?#{query}",
      headers: api_headers
    )

    if response.success?
      { success: true }
    else
      Rails.logger.error "Meta template delete failed: #{response.code} - #{response.body}"
      error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
      {
        success: false,
        error_code: error&.dig('code'),
        error_message: error&.dig('message') || response.body,
        error_details: error&.dig('error_user_msg') || error&.dig('error_data', 'details')
      }
    end
  end

  # Submits a new template for Meta approval. `payload` is the raw Meta
  # request body (matches https://developers.facebook.com/docs/whatsapp/business-management-api/message-templates)
  # so a future frontend that composes header/footer/buttons doesn't
  # need a translation layer — it forwards the shape Meta already
  # documents. Returns a normalised hash so the controller can distinguish
  # success (template goes into PENDING on the caller's WABA) from Meta
  # validation errors (bad component shape, duplicate name, category
  # policy, etc.) without parsing HTTP responses itself.
  def create_template(payload)
    response = HTTParty.post(
      "#{business_account_path}/message_templates",
      headers: api_headers,
      body: payload.to_json
    )

    if response.success?
      { success: true, template: response.parsed_response }
    else
      Rails.logger.error "Meta template create failed: #{response.code} - #{response.body}"
      error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
      {
        success: false,
        error_code: error&.dig('code'),
        error_message: error&.dig('message') || response.body,
        error_details: error&.dig('error_user_msg') || error&.dig('error_data', 'details')
      }
    end
  end

  # Meta requires templates with IMAGE/VIDEO/DOCUMENT headers to reference
  # a `header_handle` produced by the resumable upload flow — no direct
  # URL upload is allowed. We proxy the operator's file through a two-step
  # dance:
  #   1) create an upload session against `/{APP_ID}/uploads` with metadata
  #   2) POST the raw bytes to the returned session id, get the handle
  # The handle is what we hand to `create_template` inside
  # `components[].example.header_handle`; we never persist the file.
  def upload_template_header_media(file_io:, file_name:, file_type:, file_length:)
    app_id = GlobalConfigService.load('WHATSAPP_APP_ID', nil)
    return { success: false, error_message: 'WHATSAPP_APP_ID is not configured' } if app_id.blank?

    session_id = create_upload_session(app_id, file_name, file_type, file_length)
    return session_id if session_id.is_a?(Hash) && session_id[:success] == false

    upload_bytes_to_session(session_id, file_io)
  end

  def fetch_whatsapp_templates(url)
    response = HTTParty.get(url)
    return [] unless response.success?

    next_url = next_url(response)

    return response['data'] + fetch_whatsapp_templates(next_url) if next_url.present?

    response['data']
  end

  def next_url(response)
    response['paging'] ? response['paging']['next'] : ''
  end

  def validate_provider_config?
    response = HTTParty.get("#{business_account_path}/message_templates?access_token=#{whatsapp_channel.provider_config['api_key']}")
    response.success?
  end

  def api_headers
    { 'Authorization' => "Bearer #{whatsapp_channel.provider_config['api_key']}", 'Content-Type' => 'application/json' }
  end

  def create_upload_session(app_id, file_name, file_type, file_length)
    response = HTTParty.post(
      "#{api_base_path}/v22.0/#{app_id}/uploads",
      query: {
        file_name: file_name,
        file_length: file_length,
        file_type: file_type,
        access_token: whatsapp_channel.provider_config['api_key']
      }
    )
    return format_meta_upload_error('session', response) unless response.success?

    response.parsed_response['id']
  end

  # Meta's upload endpoint expects the OAuth prefix and the raw bytes as
  # body. Do NOT set Content-Type — it accepts any binary based on the
  # `file_type` we already declared when opening the session.
  def upload_bytes_to_session(session_id, file_io)
    response = HTTParty.post(
      "#{api_base_path}/v22.0/#{session_id}",
      headers: {
        'Authorization' => "OAuth #{whatsapp_channel.provider_config['api_key']}",
        'file_offset' => '0'
      },
      body: file_io.read
    )
    return format_meta_upload_error('upload', response) unless response.success?

    { success: true, handle: response.parsed_response['h'] }
  end

  def format_meta_upload_error(step, response)
    Rails.logger.error "Meta media #{step} failed: #{response.code} - #{response.body}"
    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
    {
      success: false,
      error_code: error&.dig('code'),
      error_message: error&.dig('message') || response.body,
      error_details: error&.dig('error_user_msg') || error&.dig('error_data', 'details')
    }
  end

  def create_csat_template(template_config)
    csat_template_service.create_template(template_config)
  end

  def delete_csat_template(template_name = nil)
    template_name ||= CsatTemplateNameService.csat_template_name(whatsapp_channel.inbox.id)
    csat_template_service.delete_template(template_name)
  end

  def get_template_status(template_name)
    csat_template_service.get_template_status(template_name)
  end

  def media_url(media_id)
    "#{api_base_path}/v13.0/#{media_id}"
  end

  def toggle_typing_status(typing_status, last_message:, **)
    return false unless [Events::Types::CONVERSATION_TYPING_ON, Events::Types::CONVERSATION_RECORDING].include?(typing_status)

    response = HTTParty.post(
      "#{phone_id_path('v23.0')}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        message_id: last_message.source_id,
        status: 'read',
        # NOTE: API currently only supports "typing", no "recording" status.
        typing_indicator: { type: 'text' }
      }.to_json
    )

    Rails.logger.error(response.parsed_response) unless response.success?

    response.success?
  end

  def read_messages(messages, **)
    # NOTE: Marking the last message as read automatically applies to all previous ones.
    message = messages.last
    response = HTTParty.post(
      "#{phone_id_path('v23.0')}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        message_id: message.source_id,
        status: 'read'
      }.to_json
    )

    Rails.logger.error(response.parsed_response) unless response.success?

    response.success?
  end

  private

  def csat_template_service
    @csat_template_service ||= Whatsapp::CsatTemplateService.new(whatsapp_channel)
  end

  def api_base_path
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end

  # TODO: See if we can unify the API versions and for both paths and make it consistent with out facebook app API versions
  def phone_id_path(version = 'v13.0')
    "#{api_base_path}/#{version}/#{whatsapp_channel.provider_config['phone_number_id']}"
  end

  def business_account_path
    # v14.0 is long-deprecated by Meta — several template management
    # operations (specifically delete) behave differently on newer
    # versions and interact better with the token scopes we use for
    # send/upload. Bumped to v22.0 to align with `upload_template_header_media`.
    "#{api_base_path}/v22.0/#{whatsapp_channel.provider_config['business_account_id']}"
  end

  def send_text_message(phone_number, message)
    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        context: whatsapp_reply_context(message),
        to: phone_number,
        text: { body: message.outgoing_content },
        type: 'text'
      }.to_json
    )

    process_response(response, message)
  end

  def send_attachment_message(phone_number, message)
    attachment = message.attachments.first
    type = %w[image audio video].include?(attachment.file_type) ? attachment.file_type : 'document'
    type_content = { 'link' => attachment.download_url }
    type_content['caption'] = message.outgoing_content unless %w[audio sticker].include?(type)
    type_content['filename'] = attachment.file.filename if type == 'document'
    type_content['voice'] = true if voice_message?(type, attachment)
    response = HTTParty.post(
      "#{phone_id_path('v24.0')}/messages",
      headers: api_headers,
      body: {
        :messaging_product => 'whatsapp',
        :context => whatsapp_reply_context(message),
        'to' => phone_number,
        'type' => type,
        type.to_s => type_content
      }.to_json
    )

    process_response(response, message)
  end

  def voice_message?(type, attachment)
    type == 'audio' && attachment.meta&.dig('is_recorded_audio') && attachment.file.content_type == 'audio/ogg'
  end

  def error_message(response)
    # https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/#sample-response
    response.parsed_response&.dig('error', 'message')
  end

  def template_body_parameters(template_info)
    template_body = {
      name: template_info[:name],
      language: {
        policy: 'deterministic',
        code: template_info[:lang_code]
      }
    }

    # Enhanced template parameters structure
    # Note: Legacy format support (simple parameter arrays) has been removed
    # in favor of the enhanced component-based structure that supports
    # headers, buttons, and authentication templates.
    #
    # Expected payload format from frontend:
    # {
    #   processed_params: {
    #     body: { '1': 'John', '2': '123 Main St' },
    #     header: {
    #       media_url: 'https://...',
    #       media_type: 'image',
    #       media_name: 'filename.pdf' # Optional, for document templates only
    #     },
    #     buttons: [{ type: 'url', parameter: 'otp123456' }]
    #   }
    # }
    # This gets transformed into WhatsApp API component format:
    # [
    #   { type: 'body', parameters: [...] },
    #   { type: 'header', parameters: [...] },
    #   { type: 'button', sub_type: 'url', parameters: [...] }
    # ]
    template_body[:components] = template_info[:parameters] || []

    template_body
  end

  def whatsapp_reply_context(message)
    reply_to = message.content_attributes[:in_reply_to_external_id]
    return nil if reply_to.blank?

    {
      message_id: reply_to
    }
  end

  def send_interactive_text_message(phone_number, message)
    payload = create_payload_based_on_items(message)

    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        to: phone_number,
        interactive: payload,
        type: 'interactive'
      }.to_json
    )

    process_response(response, message)
  end

  def send_reaction_message(phone_number, message)
    response = HTTParty.post(
      "#{phone_id_path('v23.0')}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to: phone_number,
        type: 'reaction',
        reaction: {
          message_id: message.content_attributes[:in_reply_to_external_id],
          emoji: message.outgoing_content
        }
      }.to_json
    )

    process_response(response, message)
  end
end

Whatsapp::Providers::WhatsappCloudService.prepend_mod_with('Whatsapp::Providers::WhatsappCloudService')
