# Read-only view of the Meta WhatsApp templates cached on each Cloud
# WhatsApp channel. Fatia 2 of the Templates Meta story — lists what
# `Whatsapp::Providers::WhatsappCloudService#sync_templates` last pulled
# from Meta, and lets the operator trigger an on-demand refresh.
#
# The heavier CRUD (create / edit / delete / status webhook) lands in
# Fatias 3-4 on top of this same controller shell.
class Api::V2::Accounts::MetaTemplatesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_inbox
  before_action :ensure_cloud_provider

  def index
    templates = @inbox.channel.message_templates || []
    render json: {
      inbox: inbox_payload(@inbox),
      templates: templates,
      last_synced_at: @inbox.channel.message_templates_last_updated
    }
  end

  # Creates a new template on Meta. Body follows Meta's
  # `/message_templates` shape verbatim (name, language, category,
  # components) so the frontend can forward it without translation and
  # a Fatia 3b that adds header / footer / buttons only touches the
  # component builder on the client. On success we synchronously refresh
  # the local cache so the caller sees the new (PENDING) row without
  # a separate GET.
  def create
    result = @inbox.channel.provider_service.create_template(create_payload)

    if result[:success]
      @inbox.channel.sync_templates
      render json: {
        template: result[:template],
        templates: @inbox.channel.reload.message_templates || [],
        last_synced_at: @inbox.channel.message_templates_last_updated
      }, status: :created
    else
      render json: {
        error: result[:error_message] || I18n.t('errors.meta_templates.create_failed'),
        details: result[:error_details],
        code: result[:error_code]
      }, status: :unprocessable_entity
    end
  end

  # Deletes a template from Meta by name. Meta scopes templates at the
  # WABA + name level, so a single call removes every language variant.
  # Resolves the name from the cached templates on the channel — the
  # frontend passes the template `id` (Meta id) as `params[:id]`, keeping
  # the RESTful URL shape without leaking the name in the path.
  def destroy
    template_name = template_name_for(params[:id])

    if template_name.nil?
      render json: { error: I18n.t('errors.meta_templates.template_not_found') }, status: :not_found
      return
    end

    result = @inbox.channel.provider_service.delete_template(template_name)

    if result[:success]
      @inbox.channel.sync_templates
      render json: {
        templates: @inbox.channel.reload.message_templates || [],
        last_synced_at: @inbox.channel.message_templates_last_updated
      }
    else
      render json: {
        error: result[:error_message] || I18n.t('errors.meta_templates.delete_failed'),
        details: result[:error_details],
        code: result[:error_code]
      }, status: :unprocessable_entity
    end
  end

  # On-demand refresh. Runs inline instead of enqueueing the job so the
  # operator gets the fresh data in the same request — Meta's list call is
  # a single roundtrip (with paging) and takes a couple of seconds.
  # Wrapped in `Whatsapp::Providers::TransientError` awareness could come
  # later; for a manual sync the error message is fine to surface as-is.
  def sync
    @inbox.channel.sync_templates
    templates = @inbox.channel.reload.message_templates || []
    render json: {
      inbox: inbox_payload(@inbox),
      templates: templates,
      last_synced_at: @inbox.channel.message_templates_last_updated
    }
  rescue StandardError => e
    Rails.logger.warn("[MetaTemplates#sync] inbox=#{@inbox.id} failed: #{e.class}: #{e.message}")
    render json: { error: I18n.t('errors.meta_templates.sync_failed') }, status: :unprocessable_entity
  end

  private

  def check_authorization
    authorize :meta_template, "#{action_name}?".to_sym
  end

  # Restricts operations to inboxes the current account actually owns; a
  # crafted `inbox_id` from another account gets a 404 instead of leaking
  # the template catalog cross-tenant.
  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  # This controller is Cloud-only. Baileys, Twilio-WhatsApp and the
  # other providers do not have Meta-approved templates in the same
  # sense, so a request against them returns 422 instead of an empty
  # payload the frontend might misread as "no templates".
  def ensure_cloud_provider
    return if @inbox.whatsapp? && @inbox.channel.try(:provider) == 'whatsapp_cloud'

    render json: { error: I18n.t('errors.meta_templates.non_cloud_inbox') }, status: :unprocessable_entity
  end

  def inbox_payload(inbox)
    channel = inbox.channel
    {
      id: inbox.id,
      name: inbox.name,
      phone_number: channel.try(:phone_number)
    }
  end

  # Looks up the template's name from the cached list on the channel.
  # We index the route by Meta template `id` (RESTful URL) but Meta's
  # DELETE endpoint accepts only `name` — this bridges the two without
  # exposing the name on the URL. Returns nil if the id is unknown, so
  # `destroy` can 404 instead of firing a delete for a name we did not
  # confirm we own.
  def template_name_for(template_id)
    templates = @inbox.channel.message_templates || []
    match = templates.find { |t| t['id'].to_s == template_id.to_s }
    match&.dig('name')
  end

  # Whitelists the four top-level Meta fields and forwards the
  # `components` array to Meta as-is. Strong-params can't cleanly model
  # Meta's typed-and-nested component schema (BODY/HEADER/FOOTER/BUTTONS,
  # each with their own keys), and enumerating every leaf would drift
  # out of sync with their API. Using `to_unsafe_h` here is safe: we
  # forward the shape to Meta (they validate and reject anything bad)
  # and persist nothing from it directly.
  def create_payload
    root = params.require(:template).to_unsafe_h.stringify_keys
    root.slice('name', 'language', 'category', 'components')
  end
end
