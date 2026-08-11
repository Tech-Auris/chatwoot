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

  # Updates an existing template on Meta. The frontend passes the Meta
  # template `id` in the URL and the same Meta-shaped payload the create
  # flow uses. Meta refuses edits on some (status, field) combinations —
  # we surface the rejection message as 422 instead of trying to mirror
  # the rule matrix in this controller.
  def update
    if template_name_for(params[:id]).nil?
      render json: { error: I18n.t('errors.meta_templates.template_not_found') }, status: :not_found
      return
    end

    result = @inbox.channel.provider_service.update_template(params[:id], update_payload)
    render_provider_write_result(result, fallback_key: 'meta_templates.update_failed')
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

  # Per-template send funnel derived from our own outgoing messages: how
  # many attempts, how many Meta accepted (source_id present), how many
  # were later delivered / read / failed. The frontend renders this inside
  # the detail drawer with a 7d / 30d / 90d switcher — invalid period
  # values fall back to 30d in the service.
  def analytics
    template = find_template_or_render_404
    return if template.nil?

    render json: Whatsapp::TemplateAnalyticsService.new(
      inbox: @inbox,
      template_name: template['name'],
      template_language: template['language'],
      period: params[:period]
    ).call
  end

  # Proxies an operator-uploaded media file through Meta's resumable
  # upload flow and returns just the `header_handle` — the frontend
  # stashes it in the form state and includes it in `components[].example.
  # header_handle` when submitting the template. We never persist the
  # file on our side (see `Whatsapp::Providers::WhatsappCloudService#
  # upload_template_header_media` for the two-step details).
  # MVP: images only. Meta size limit for header images is 5 MB — we cap
  # here so the request is rejected early instead of failing on Meta's
  # side after a full body upload.
  ALLOWED_HEADER_MEDIA_TYPES = %w[image/jpeg image/png].freeze
  MAX_HEADER_MEDIA_BYTES = 5.megabytes

  def upload_header_media
    file = params[:file]
    return render_upload_error(:unprocessable_entity, 'A file is required') if file.blank?

    unless ALLOWED_HEADER_MEDIA_TYPES.include?(file.content_type)
      return render_upload_error(:unprocessable_entity, "Unsupported file type: #{file.content_type}")
    end
    return render_upload_error(:unprocessable_entity, 'File exceeds the 5 MB limit') if file.size > MAX_HEADER_MEDIA_BYTES

    result = @inbox.channel.provider_service.upload_template_header_media(
      file_io: file.tempfile, file_name: file.original_filename, file_type: file.content_type, file_length: file.size
    )

    if result[:success]
      render json: { handle: result[:handle] }
    else
      render_upload_error(:unprocessable_entity, result[:error_message], details: result[:error_details], code: result[:error_code])
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

  # Shared renderer for create/update responses: on success, refresh the
  # local cache (Meta already accepted the write) and echo back the
  # fresh list; on failure, surface Meta's error text + details + code
  # so the operator sees exactly what was rejected instead of a generic
  # "try again". Kept as a helper so #update stays compact — Rubocop
  # was flagging the method length otherwise.
  def render_provider_write_result(result, fallback_key:, success_status: :ok)
    if result[:success]
      @inbox.channel.sync_templates
      render json: {
        template: result[:template],
        templates: @inbox.channel.reload.message_templates || [],
        last_synced_at: @inbox.channel.message_templates_last_updated
      }, status: success_status
    else
      render json: {
        error: result[:error_message] || I18n.t("errors.#{fallback_key}"),
        details: result[:error_details],
        code: result[:error_code]
      }, status: :unprocessable_entity
    end
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

  def render_upload_error(status, message, details: nil, code: nil)
    render json: { error: message, details: details, code: code }.compact, status: status
  end

  def find_template_or_render_404
    templates = @inbox.channel.message_templates || []
    match = templates.find { |t| t['id'].to_s == params[:id].to_s }
    return match if match

    render json: { error: I18n.t('errors.meta_templates.template_not_found') }, status: :not_found
    nil
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

  # Meta's update endpoint accepts `category` and `components` only;
  # name and language are immutable once the template is created. Slice
  # here so the frontend can send the full form shape without a special
  # transformer, and we only forward what Meta allows.
  def update_payload
    root = params.require(:template).to_unsafe_h.stringify_keys
    root.slice('category', 'components')
  end
end
