class Whatsapp::TemplateAnalyticsService
  # Derives a per-template usage funnel from our own `messages` table — no
  # extra Meta call. Every template send goes through SendOnWhatsappService
  # which stores `additional_attributes.template_params.{name,language}` on
  # the message, so we can filter and count locally.
  #
  # Funnel semantics (see Whatsapp::Providers::BaseService#handle_error and
  # SendOnWhatsappService#send_template_message for where these transitions
  # get written):
  # - sent               → every attempt, regardless of outcome
  # - failed_sync        → Meta rejected the request synchronously
  #                        (status=failed, source_id nil)
  # - accepted_by_meta   → Meta returned a wamid (source_id present).
  #                        Includes messages that later failed post-accept.
  # - delivered          → Meta status webhook flipped it to delivered/read
  # - read               → subset of delivered where read receipt arrived
  # - failed_after_accept → Meta accepted but a later status webhook flipped
  #                        it to failed (undeliverable, number invalid, etc.)
  ALLOWED_PERIODS = { '7d' => 7, '30d' => 30, '90d' => 90 }.freeze

  def initialize(inbox:, template_name:, template_language:, period: '30d')
    @inbox = inbox
    @template_name = template_name
    @template_language = template_language&.downcase
    @period_key = ALLOWED_PERIODS.key?(period) ? period : '30d'
  end

  def call
    # `reorder(nil)` strips the default `created_at` order from the Message
    # scope — without it Postgres refuses `GROUP BY status` because the
    # order column isn't in the grouping.
    counts = base_scope.reorder(nil).group(:status).count.transform_keys(&:to_s)
    accepted = base_scope.where.not(source_id: nil).count
    sent = counts.values.sum

    {
      period: @period_key,
      period_days: ALLOWED_PERIODS[@period_key],
      template_name: @template_name,
      template_language: @template_language,
      funnel: {
        sent: sent,
        accepted_by_meta: accepted,
        failed_sync: sent - accepted,
        delivered: counts.fetch('delivered', 0) + counts.fetch('read', 0),
        read: counts.fetch('read', 0),
        failed_after_accept: base_scope.where(status: :failed).where.not(source_id: nil).count
      }
    }
  end

  private

  def base_scope
    period_days = ALLOWED_PERIODS[@period_key]
    Message.where(inbox_id: @inbox.id, message_type: :outgoing)
           .where(created_at: period_days.days.ago..)
           .where("additional_attributes -> 'template_params' ->> 'name' = ?", @template_name)
           .where("LOWER(additional_attributes -> 'template_params' ->> 'language') = ?", @template_language)
  end
end
