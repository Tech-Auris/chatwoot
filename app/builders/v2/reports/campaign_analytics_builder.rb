# Aggregates the Fase 3 Analytics report — one row per Meta ad the account
# has seen (either as a conversation's `campaign_referral.source_id` or as a
# `campaign_spends.source_id`). Google Ads campaigns are appended as
# spend-only rows because our conversation-side attribution (Fase 1.5) does
# not tie a conversation to a specific Google campaign.
#
# Row shape:
#   * source_type      — "meta_ad" | "google_ads_campaign"
#   * source_id        — ad_id (Meta) or campaign_id (Google)
#   * name             — ad title (Meta) or campaign name (Google), pulled
#                        from campaign_referral / campaign_spend metadata
#   * conversations_count, qualified_count, scheduled_count, attendance_count
#   * revenue_cents    — attendance_count × Account.average_ticket
#   * spend_cents      — SUM of campaign_spends.amount_cents in the period
#   * cpl_cents, cpa_cents, roas — derived (nil when denominator is 0)
class V2::Reports::CampaignAnalyticsBuilder
  include DateRangeHelper

  QUALIFYING_STAGE_NAME = 'Em Qualificação'.freeze
  SCHEDULING_CHART_GROUP = 'Agendamento'.freeze
  ATTENDANCE_STAGE_NAME = 'Comparecimento (ganho)'.freeze

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    rows = meta_rows.values
    rows += google_rows
    rows.sort_by { |row| -(row[:spend_cents] || 0) }
  end

  private

  # ---- Meta rows ----------------------------------------------------------

  def meta_rows
    @meta_rows ||= begin
      all_ids = conversation_agg_by_ad.keys | meta_spend_by_ad.keys
      all_ids.index_with { |ad_id| build_meta_row(ad_id) }
    end
  end

  def build_meta_row(ad_id) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    conv = conversation_agg_by_ad[ad_id] || { count: 0, sample_name: nil }
    stages = stage_counts_by_ad[ad_id] || {}
    spent_cents = meta_spend_by_ad[ad_id] || 0
    attendance = stages[:attendance] || 0
    revenue_cents = attendance * average_ticket_cents

    {
      source_type: 'meta_ad',
      source_id: ad_id,
      name: conv[:sample_name],
      conversations_count: conv[:count],
      qualified_count: stages[:qualifying] || 0,
      scheduled_count: stages[:scheduling] || 0,
      attendance_count: attendance,
      revenue_cents: revenue_cents,
      spend_cents: spent_cents,
      cpl_cents: safe_div(spent_cents, stages[:qualifying]),
      cpa_cents: safe_div(spent_cents, attendance),
      roas: (spent_cents.positive? && revenue_cents.positive? ? (revenue_cents.to_f / spent_cents).round(2) : nil)
    }
  end

  # Groups conversations by `campaign_referral.source_id`. `sample_name` is
  # the first referral title we see for that ad — the operator sees the ad
  # copy without having to click through, and Meta's ad names are stable
  # enough across the period that any row's title is representative.
  def conversation_agg_by_ad
    @conversation_agg_by_ad ||= begin
      rows = ActiveRecord::Base.connection.select_all(<<~SQL.squish)
        SELECT
          additional_attributes->'campaign_referral'->>'source_id' AS ad_id,
          COUNT(*) AS conversations_count,
          MIN(additional_attributes->'campaign_referral'->>'title') AS sample_name
        FROM conversations
        WHERE account_id = #{account.id}
          AND additional_attributes->'campaign_referral'->>'source_id' IS NOT NULL
          #{period_sql('conversations.created_at')}
        GROUP BY ad_id
      SQL
      rows.each_with_object({}) do |row, acc|
        acc[row['ad_id']] = { count: row['conversations_count'].to_i, sample_name: row['sample_name'] }
      end
    end
  end

  def stage_counts_by_ad # rubocop:disable Metrics/MethodLength
    @stage_counts_by_ad ||= begin
      rows = ActiveRecord::Base.connection.select_all(<<~SQL.squish)
        SELECT
          c.additional_attributes->'campaign_referral'->>'source_id' AS ad_id,
          COUNT(*) FILTER (WHERE fsc.new_stage = '#{QUALIFYING_STAGE_NAME}') AS qualifying,
          COUNT(*) FILTER (WHERE fsc.new_stage IN (#{scheduling_stage_names_sql})) AS scheduling,
          COUNT(*) FILTER (WHERE fsc.new_stage = '#{ATTENDANCE_STAGE_NAME}') AS attendance
        FROM funnel_stage_changes fsc
        JOIN conversations c ON c.id = fsc.conversation_id
        WHERE fsc.account_id = #{account.id}
          AND c.additional_attributes->'campaign_referral'->>'source_id' IS NOT NULL
          #{period_sql('fsc.created_at')}
        GROUP BY ad_id
      SQL
      rows.each_with_object({}) do |row, acc|
        acc[row['ad_id']] = {
          qualifying: row['qualifying'].to_i,
          scheduling: row['scheduling'].to_i,
          attendance: row['attendance'].to_i
        }
      end
    end
  end

  def scheduling_stage_names_sql
    names = FunnelStage.active.where(chart_group: SCHEDULING_CHART_GROUP).pluck(:name)
    return "''" if names.empty?

    names.map { |name| ActiveRecord::Base.connection.quote(name) }.join(', ')
  end

  def meta_spend_by_ad
    @meta_spend_by_ad ||= account.campaign_spends
                                 .where(provider: :meta, source_type: 'meta_ad')
                                 .then { |scope| range.present? ? scope.in_period(range.first.to_date, range.last.to_date) : scope }
                                 .group(:source_id).sum(:amount_cents)
  end

  # ---- Google rows --------------------------------------------------------

  def google_rows
    account.campaign_spends
           .where(provider: :google_ads)
           .then { |scope| range.present? ? scope.in_period(range.first.to_date, range.last.to_date) : scope }
           .group(:source_id).sum(:amount_cents)
           .map { |campaign_id, spent_cents| build_google_row(campaign_id, spent_cents) }
  end

  def build_google_row(campaign_id, spent_cents)
    sample_name = account.campaign_spends
                         .where(provider: :google_ads, source_id: campaign_id)
                         .pick(Arel.sql("external_metadata->'campaign'->>'name'"))
    {
      source_type: 'google_ads_campaign',
      source_id: campaign_id,
      name: sample_name,
      conversations_count: 0,
      qualified_count: 0,
      scheduled_count: 0,
      attendance_count: 0,
      revenue_cents: 0,
      spend_cents: spent_cents,
      cpl_cents: nil,
      cpa_cents: nil,
      roas: nil
    }
  end

  # ---- Helpers ------------------------------------------------------------

  def average_ticket_cents
    (account.average_ticket.to_f * 100).round
  end

  def safe_div(numerator, denominator)
    return nil if numerator.to_i.zero? || denominator.to_i.zero?

    (numerator / denominator).round
  end

  # DateRangeHelper#range returns nil when the params don't have both
  # bounds — treat that as "all time" instead of returning an empty scope.
  def period_sql(column)
    return '' if range.blank?

    "AND #{column} BETWEEN #{ActiveRecord::Base.connection.quote(range.first)} AND #{ActiveRecord::Base.connection.quote(range.last)}"
  end
end
