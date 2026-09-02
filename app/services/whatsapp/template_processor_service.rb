class Whatsapp::TemplateProcessorService
  pattr_initialize [:channel!, :template_params, :message]

  def call
    return [nil, nil, nil, nil] if template_params.blank?

    process_template_with_params
  end

  private

  def process_template_with_params
    [
      template_params['name'],
      template_params['namespace'],
      template_params['language'],
      processed_templates_params
    ]
  end

  def find_template
    channel.message_templates.find do |t|
      t['name'] == template_params['name'] &&
        t['language']&.downcase == template_params['language']&.downcase &&
        t['status']&.downcase == 'approved'
    end
  end

  def processed_templates_params
    template = find_template
    return if template.blank?

    # Convert legacy format to enhanced format before processing
    converter = Whatsapp::TemplateParameterConverterService.new(template_params, template)
    normalized_params = converter.normalize_to_enhanced

    process_enhanced_template_params(template, normalized_params['processed_params'])
  end

  def process_enhanced_template_params(template, processed_params = nil)
    processed_params ||= template_params['processed_params']
    components = []

    components.concat(process_header_components(processed_params, template))
    components.concat(process_body_components(processed_params, template))
    components.concat(process_footer_components(processed_params))
    components.concat(process_button_components(processed_params))

    @template_params = components
  end

  def process_header_components(processed_params, template)
    return [] if processed_params['header'].blank?

    header_params = build_header_params(processed_params['header'], template)
    header_params.present? ? [{ type: 'header', parameters: header_params }] : []
  end

  # Header text parameters must mirror the template's parameter_format —
  # a NAMED template rejects positional header params (Meta returns
  # #132000 "Number of parameters does not match the expected number of
  # params" even when the count matches, because it can't map the value
  # back to the named placeholder). Media parameters are always shaped
  # by their media type, so parameter_format doesn't apply there.
  # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def build_header_params(header_data, template)
    parameter_format = template['parameter_format']
    cached_media_id = template['header_media_id']
    cached_media_type = cached_media_type_for(template)
    header_params = []
    header_data.each do |key, value|
      next if value.blank?

      if media_url_with_type?(key, header_data)
        # Prefer the cached media_id when we have one — it survives the
        # preview-URL expiry that causes Meta's 131053 on send. Falls
        # back to the URL only when the sync has not resolved an id yet
        # (fresh template, or upload failed and we're mid-recovery).
        media_name = header_data['media_name']
        media_param = if cached_media_id.present?
                        parameter_builder.build_media_id_parameter(cached_media_type || header_data['media_type'],
                                                                   cached_media_id, media_name)
                      else
                        parameter_builder.build_media_parameter(value, header_data['media_type'], media_name)
                      end
        header_params << media_param if media_param
      elsif key != 'media_type' && key != 'media_name'
        header_params << text_header_param(key, value, parameter_format)
      end
    end
    header_params
  end
  # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def cached_media_type_for(template)
    header = Array(template['components']).find { |c| c['type']&.upcase == 'HEADER' }
    header&.dig('format')&.to_s&.downcase
  end

  def text_header_param(key, value, parameter_format)
    if parameter_format == 'NAMED'
      parameter_builder.build_named_parameter(key, value)
    else
      parameter_builder.build_parameter(value)
    end
  end

  def media_url_with_type?(key, header_data)
    key == 'media_url' && header_data['media_type'].present?
  end

  def process_body_components(processed_params, template)
    return [] if processed_params['body'].blank?

    body_params = processed_params['body'].filter_map do |key, value|
      next if value.blank?

      parameter_format = template['parameter_format']
      if parameter_format == 'NAMED'
        parameter_builder.build_named_parameter(key, value)
      else
        parameter_builder.build_parameter(value)
      end
    end

    body_params.present? ? [{ type: 'body', parameters: body_params }] : []
  end

  def process_footer_components(processed_params)
    return [] if processed_params['footer'].blank?

    footer_params = processed_params['footer'].filter_map do |_, value|
      next if value.blank?

      parameter_builder.build_parameter(value)
    end

    footer_params.present? ? [{ type: 'footer', parameters: footer_params }] : []
  end

  def process_button_components(processed_params)
    return [] if processed_params['buttons'].blank?

    button_params = processed_params['buttons'].filter_map.with_index do |button, index|
      next if button.blank?

      if button['type'] == 'url' || button['parameter'].present?
        {
          type: 'button',
          sub_type: button['type'] || 'url',
          index: index,
          parameters: [parameter_builder.build_button_parameter(button)]
        }
      end
    end

    button_params.compact
  end

  def parameter_builder
    @parameter_builder ||= Whatsapp::PopulateTemplateParametersService.new
  end
end
