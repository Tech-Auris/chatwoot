class Whatsapp::TemplateProcessorService
  pattr_initialize [:channel!, :template_params, :message]

  MEDIA_KEYS = %w[media_url media_type media_name].freeze
  # Meta's own preview of the template image (`example.header_handle`);
  # Meta refuses it back on send with 131053, so it counts as no URL.
  META_PREVIEW_URL = %r{\Ahttps://scontent\.whatsapp\.net/}

  def self.custom_header_url(header_data)
    url = header_data&.dig('media_url')
    url if url.present? && !url.match?(META_PREVIEW_URL)
  end

  def self.template_header_url(template)
    header = Array(template['components']).find { |c| c['type']&.upcase == 'HEADER' }
    Array(header&.dig('example', 'header_handle')).first
  end

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
  def build_header_params(header_data, template)
    text_params = header_data.except(*MEDIA_KEYS).filter_map do |key, value|
      text_header_param(key, value, template['parameter_format']) if value.present?
    end
    [header_media_param(header_data, template), *text_params].compact
  end

  # The operator's own URL wins. Left blank, the header carries the
  # template's own image: the media_id the sync cached, or else Meta's
  # preview URL, whose 131053 the send flow recovers from by caching an id.
  def header_media_param(header_data, template)
    return if header_data['media_type'].blank?

    media_type = cached_media_type_for(template) || header_data['media_type']
    media_name = header_data['media_name']
    custom_url = self.class.custom_header_url(header_data)
    return parameter_builder.build_media_parameter(custom_url, media_type, media_name) if custom_url
    return parameter_builder.build_media_id_parameter(media_type, template['header_media_id'], media_name) if template['header_media_id'].present?

    parameter_builder.build_media_parameter(self.class.template_header_url(template), media_type, media_name)
  end

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
