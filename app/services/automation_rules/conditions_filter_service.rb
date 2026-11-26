require 'json'

class AutomationRules::ConditionsFilterService < FilterService
  ATTRIBUTE_MODEL = 'contact_attribute'.freeze

  def initialize(rule, conversation = nil, options = {})
    super([], nil)
    # assign rule, conversation and account to instance variables
    @rule = rule
    @conversation = conversation
    @account = conversation.account

    # setup filters from json file
    file = File.read('./lib/filters/filter_keys.yml')
    @filters = YAML.safe_load(file)

    @conversation_filters = @filters['conversations']
    @contact_filters = @filters['contacts']
    @message_filters = @filters['messages']

    @options = options
    @changed_attributes = options[:changed_attributes]
  end

  def perform
    return false unless rule_valid?

    @attribute_changed_query_filter = []

    @rule.conditions.each_with_index do |query_hash, current_index|
      @attribute_changed_query_filter << query_hash and next if query_hash['filter_operator'] == 'attribute_changed'

      apply_filter(query_hash, current_index)
    end

    records = base_relation.where(@query_string, @filter_values.with_indifferent_access)
    records = perform_attribute_changed_filter(records) if @attribute_changed_query_filter.any?

    records.any?
  rescue StandardError => e
    Rails.logger.error "Error in AutomationRules::ConditionsFilterService: #{e.message}"
    Rails.logger.info "AutomationRules::ConditionsFilterService failed while processing rule #{@rule.id} for conversation #{@conversation.id}"
    false
  end

  def rule_valid?
    is_valid = AutomationRules::ConditionValidationService.new(@rule).perform
    Rails.logger.info "Automation rule condition validation failed for rule id: #{@rule.id}" unless is_valid
    @rule.authorization_error! unless is_valid

    is_valid
  end

  def filter_operation(query_hash, current_index)
    if query_hash[:filter_operator] == 'starts_with'
      @filter_values["value_#{current_index}"] = "#{string_filter_values(query_hash)}%"
      like_filter_string(query_hash[:filter_operator], current_index)
    else
      super
    end
  end

  def apply_filter(query_hash, current_index)
    # A declared custom_attribute_type means an account attribute. Message keys are not reserved names,
    # so an account attribute called `sender_id` would otherwise be answered by the message column.
    return apply_custom_attribute_filter(query_hash, current_index) if query_hash['custom_attribute_type'].present?

    conversation_filter = @conversation_filters[query_hash['attribute_key']]
    contact_filter = @contact_filters[query_hash['attribute_key']]
    message_filter = @message_filters[query_hash['attribute_key']]

    if conversation_filter
      @query_string += conversation_query_string('conversations', conversation_filter, query_hash.with_indifferent_access, current_index)
    elsif contact_filter
      @query_string += contact_query_string(contact_filter, query_hash.with_indifferent_access, current_index)
    elsif message_filter
      @query_string += message_query_string(message_filter, query_hash.with_indifferent_access, current_index)
    else
      apply_custom_attribute_filter(query_hash, current_index)
    end
  end

  # custom_attribute_query answers '' when the account has no attribute by that name.
  def apply_custom_attribute_filter(query_hash, current_index)
    @query_string += custom_attribute_query(query_hash.with_indifferent_access, query_hash['custom_attribute_type'], current_index)
  end

  # If attribute_changed type filter is present perform this against array
  def perform_attribute_changed_filter(records)
    @attribute_changed_records = []
    current_attribute_changed_record = base_relation
    filter_based_on_attribute_change(records, current_attribute_changed_record)

    @attribute_changed_records.uniq
  end

  # Loop through attribute_changed_query_filter
  def filter_based_on_attribute_change(records, current_attribute_changed_record)
    @attribute_changed_query_filter.each do |filter|
      @changed_attributes = @changed_attributes.with_indifferent_access
      changed_attribute = @changed_attributes[filter['attribute_key']].presence

      if changed_attribute[0].in?(filter['values']['from']) && changed_attribute[1].in?(filter['values']['to'])
        @attribute_changed_records = attribute_changed_filter_query(filter, records, current_attribute_changed_record)
      end
      current_attribute_changed_record = @attribute_changed_records
    end
  end

  # We intersect with the record if query_operator-AND is present and union if query_operator-OR is present
  def attribute_changed_filter_query(filter, records, current_attribute_changed_record)
    if filter['query_operator'] == 'AND'
      @attribute_changed_records + (current_attribute_changed_record & records)
    else
      @attribute_changed_records + (current_attribute_changed_record | records)
    end
  end

  def message_query_string(current_filter, query_hash, current_index)
    attribute_key = query_hash['attribute_key']
    query_operator = query_hash['query_operator']

    return sender_id_query_string(query_hash, current_index) if attribute_key == 'sender_id'

    attribute_key = 'processed_message_content' if attribute_key == 'content'
    attribute_key = 'private' if attribute_key == 'private_note'

    filter_operator_value = filter_operation(query_hash, current_index)

    case current_filter['attribute_type']
    when 'standard'
      if current_filter['data_type'] == 'text'
        " LOWER(messages.#{attribute_key}) #{filter_operator_value} #{query_operator} "
      else
        " messages.#{attribute_key} #{filter_operator_value} #{query_operator} "
      end
    end
  end

  # The Sender condition offers agents, so it always means an agent: messages.sender_id is polymorphic,
  # and a contact holding the same id must not match. A message without a sender never matches.
  def sender_id_query_string(query_hash, current_index)
    membership = filter_operation(query_hash.merge('filter_operator' => 'equal_to'), current_index)
    negation = query_hash['filter_operator'] == 'not_equal_to' ? 'NOT ' : ''
    " #{negation}(messages.sender_type = 'User' AND messages.sender_id #{membership}) #{query_hash['query_operator']} "
  end

  # This will be used in future for contact automation rule
  def contact_query_string(current_filter, query_hash, current_index)
    attribute_key = query_hash['attribute_key']
    query_operator = query_hash['query_operator']

    filter_operator_value = filter_operation(query_hash, current_index)

    case current_filter['attribute_type']
    when 'additional_attributes'
      " contacts.additional_attributes ->> '#{attribute_key}' #{filter_operator_value} #{query_operator} "
    when 'standard'
      " contacts.#{attribute_key} #{filter_operator_value} #{query_operator} "
    end
  end

  def conversation_query_string(table_name, current_filter, query_hash, current_index)
    attribute_key = query_hash['attribute_key']
    query_operator = query_hash['query_operator']
    return assignee_presence_filter(table_name, query_hash) if assignee_presence_condition?(query_hash)
    return tag_filter_query(query_hash, current_index) if attribute_key == 'labels'

    filter_operator_value = filter_operation(query_hash, current_index)

    case current_filter['attribute_type']
    when 'additional_attributes'
      " #{table_name}.additional_attributes ->> '#{attribute_key}' #{filter_operator_value} #{query_operator} "
    when 'contact_additional_attributes'
      # `base_relation` already LEFT JOINs contacts on conversation.contact_id,
      # so conversation-scoped filters that live on the contact (like `origem`)
      # can reach the column directly.
      " contacts.additional_attributes ->> '#{attribute_key}' #{filter_operator_value} #{query_operator} "
    when 'pipeline_entry'
      pipeline_stage_condition(query_hash, current_index)
    when 'standard'
      " #{table_name}.#{attribute_key} #{filter_operator_value} #{query_operator} "
    end
  end

  private

  def assignee_presence_condition?(query_hash)
    query_hash['attribute_key'] == 'assignee_id' && query_hash['filter_operator'].in?(%w[is_present is_not_present])
  end

  # Assignee ownership can live in either column until it is standardized as a polymorphic association.
  def assignee_presence_filter(table_name, query_hash)
    if query_hash[:filter_operator] == 'is_present'
      return "(#{table_name}.assignee_id IS NOT NULL OR #{table_name}.assignee_agent_bot_id IS NOT NULL) #{query_hash[:query_operator]}"
    end

    "(#{table_name}.assignee_id IS NULL AND #{table_name}.assignee_agent_bot_id IS NULL) #{query_hash[:query_operator]}"
  end

  def filter_config
    {
      entity: 'Conversation',
      table_name: 'conversations'
    }
  end

  def base_relation
    records = Conversation.where(id: @conversation.id).joins(
      'LEFT OUTER JOIN contacts on conversations.contact_id = contacts.id'
    ).joins(
      'LEFT OUTER JOIN messages on messages.conversation_id = conversations.id'
    )

    records = records.where(messages: { id: @options[:message].id }) if @options[:message].present?
    records
  end
end
