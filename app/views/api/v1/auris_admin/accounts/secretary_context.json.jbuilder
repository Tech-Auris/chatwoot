json.id @account.id
json.name @account.name
secretary = @account.account_secretary

if @sections.include?('account')
  json.account do
    json.status @account.status
    json.flags @account.auris_settings
    json.erp_source @account.erp_source && { id: @account.erp_source.id, name: @account.erp_source.name }
  end
end

if @sections.include?('secretary')
  json.secretary do
    json.version secretary&.secretary_version&.name
    # nil means the Simulador runs the account's version ("Mesma da conta").
    json.simulator_version secretary&.simulator_version&.name
    json.ai_provider secretary&.ai_model&.ai_provider&.name
    json.ai_model secretary&.ai_model&.name
    json.secret_present secretary&.secret.present? || false
    json.enabled_inboxes @account.inboxes.where(secretary_enabled: true).order(:id) do |inbox|
      json.id inbox.id
      json.name inbox.name
    end
  end
end

if @sections.include?('follow_up')
  json.follow_up do
    end_flow = @account.follow_up&.dig('end_flow') || {}
    json.steps @account.follow_up&.dig('steps') || []
    json.escalate_on_end ActiveModel::Type::Boolean.new.cast(end_flow['enabled']) || false
    json.end_wait_minutes @account.follow_up_end_wait_minutes
    json.end_wait_is_default end_flow['wait_minutes'].blank?
    json.summary_message end_flow['summary_message']
    json.escalation_message end_flow['escalation_message']
  end
end

# "Configuração da IA": nil while the account still reads it from Supabase.
json.ai_config @account.ai_config if @sections.include?('ai_config')

if @sections.include?('prompts')
  json.prompts @account.account_prompts.order(:id) do |prompt|
    json.name prompt.name
    json.general prompt.general?
    json.inboxes(prompt.inbox_ids.map { |inbox_id| { id: inbox_id, name: @inbox_names[inbox_id] } })
    json.text prompt.ai_prompt_system_message
    json.updated_at prompt.updated_at
  end
end

if @sections.include?('special_scenarios')
  json.special_scenarios @account.secretary_special_scenarios.order(:name) do |scenario|
    json.extract! scenario, :name, :situacao, :gatilho, :instrucao
  end
end

if @sections.include?('resources')
  json.resources @account.secretary_resources.includes(:secretary_resource_type).order(:key, :idioma) do |resource|
    json.extract! resource, :key, :idioma, :caption, :resource_url
    json.type resource.secretary_resource_type.description
  end
end

if @sections.include?('confirmations')
  json.confirmations do
    json.reminders @account.secretary_confirmations.order(:id) do |confirmation|
      json.extract! confirmation, :id, :versao_workflow, :inbox_id, :calendar_id, :unidade_id, :message,
                    :message_96h, :message_72h, :message_48h, :message_hj, :message_2h, :message_30m
      json.inbox_name @inbox_names[confirmation.inbox_id.to_i]
    end
    send_logs = @account.secretary_confirmation_send_logs
    json.sent_last_7_days send_logs.where(sent_at: 7.days.ago..).group(:reminder_type).count
    json.last_sent_at send_logs.maximum(:sent_at)
  end
end
