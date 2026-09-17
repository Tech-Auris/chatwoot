# rubocop:disable Metrics/ClassLength — three orthogonal concerns (display
# groups, KPI math, loss-reason aggregation) live here on purpose; extracting
# either would mean threading account/params/range plumbing across builders
# for a marginal LOC reduction.
class V2::Reports::FunnelConversionBuilder
  include DateRangeHelper

  # KPI denominators are all "total de leads" — distinct conversations that
  # entered the first open funnel stage in the period. The other three KPIs
  # are read off specific stage identities below. Names are Auris funnel
  # canon (set/maintained by the chart-rules data migration); changing them
  # on FunnelStage means updating these constants in lockstep.
  SCHEDULING_CHART_GROUP = 'Agendamento'.freeze
  CONFIRMATION_STAGE_NAME = 'Confirmado'.freeze
  ATTENDANCE_STAGE_NAME = 'Comparecimento (ganho)'.freeze
  NO_SHOW_STAGE_NAME = 'No-Show'.freeze

  # Per-ad breakdown columns. Same funnel canon as the KPI strip; kept as
  # separate constants so a rename of a stage forces an explicit tick here.
  QUALIFYING_STAGE_NAME = 'Em Qualificação'.freeze

  # Special origem value that means "conversations whose contact has no origem
  # set" (Sem Origem in the UI). Kept lexically distinct from the operator-
  # facing labels to avoid a collision if someone ever names a real origin
  # "none".
  ORIGEM_NONE_TOKEN = '__none__'.freeze

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    all_stages = FunnelStage.active.ordered.to_a
    return { stages: [], kpis: empty_kpis, loss_reasons: [], campaign_breakdown: [] } if all_stages.empty?

    # KPIs always look at the FULL set of active stages — visibility/merge
    # rules are presentation-only and shouldn't change "completed" or "won"
    # arithmetic. The chart, on the other hand, walks the display groups.
    display_groups = build_display_groups(all_stages)
    rows = display_groups.any? ? fetch_stage_change_rows(display_groups) : []
    group_counts = build_group_counts(display_groups, rows)
    universe = universe_counts_from(rows)
    # The first bar's count is the universe of conversations that moved
    # anywhere in the funnel during the period, not just entries into
    # the first stage. Otherwise a conversation that entered the first
    # stage BEFORE the period and only moved to a later stage INSIDE the
    # period gets counted in that later bar but not in the first — and
    # the funnel visualization ends up with a downstream bar bigger than
    # "Total de leads", which operators read (correctly) as broken.
    group_counts[display_groups.first[:key]] = universe if display_groups.any?
    stage_rows = build_stage_rows(display_groups, group_counts)

    {
      stages: stage_rows,
      kpis: build_kpis(all_stages, universe[:count]),
      loss_reasons: build_loss_reasons_breakdown,
      campaign_breakdown: build_campaign_breakdown(all_stages)
    }
  end

  private

  # A "display group" is what shows up as one column in the chart. Either:
  #   - one stage with chart_visible=true and no chart_group (group of size 1)
  #   - several stages sharing the same chart_group (collapsed into one)
  # Hidden stages (chart_visible=false) never enter a group.
  def build_display_groups(stages)
    grouped, singles = partition_by_chart_group(stages.select(&:chart_visible))
    groups = singles.map { |stage| single_stage_group(stage) }
    grouped.each do |group_name, members|
      groups << merged_group(group_name, members)
    end
    groups.sort_by { |g| g[:position] }
  end

  def partition_by_chart_group(stages)
    grouped = {}
    singles = []
    stages.each do |stage|
      if stage.chart_group.present?
        grouped[stage.chart_group] ||= []
        grouped[stage.chart_group] << stage
      else
        singles << stage
      end
    end
    [grouped, singles]
  end

  def single_stage_group(stage)
    {
      key: stage.name,
      display_name: stage.chart_display_name.presence || stage.name,
      color: stage.color,
      position: stage.position,
      closed: stage.closed,
      stage_names: [stage.name],
      stage_id: stage.id
    }
  end

  # When stages collapse, the group name becomes the visible label, the first
  # member's color seeds the bar, position uses the earliest member so the
  # group lands where its first underlying stage would have. `closed` flips
  # true only if ALL members are closed — a mixed group is treated as open.
  def merged_group(group_name, members)
    {
      key: group_name,
      display_name: group_name,
      color: members.first.color,
      position: members.map(&:position).min,
      closed: members.all?(&:closed),
      stage_names: members.map(&:name),
      stage_id: nil
    }
  end

  # Counts the distinct conversation ids that entered ANY member stage of each
  # group within the period, split by the conversation's CURRENT `ai_enabled`
  # state. Returns `{ count, count_ai, count_manual }` per group. Reentries by
  # the same conversation still count once (matches the rest of the funnel).
  # Callers pass rows in so the DB roundtrip is shared with `universe_counts_from`.
  def build_group_counts(groups, rows)
    groups.each_with_object({}) do |group, acc|
      acc[group[:key]] = split_counts_for(group, rows)
    end
  end

  # Universe = every distinct conversation that had at least one stage change
  # into a chart-visible stage during the period. Used both as the first
  # bar's count (so the funnel tapers monotonically) and as the KPI
  # denominator (so all rates are anchored on the same "leads seen in the
  # period" number). Split by ai/manual using the same rule as per-group counts.
  def universe_counts_from(rows)
    ai_ids = Set.new
    manual_ids = Set.new
    rows.each do |_new_stage, conv_id, ai_enabled|
      (ai_enabled ? ai_ids : manual_ids) << conv_id
    end
    { count: ai_ids.size + manual_ids.size, count_ai: ai_ids.size, count_manual: manual_ids.size }
  end

  def fetch_stage_change_rows(groups)
    all_names = groups.flat_map { |g| g[:stage_names] }.uniq
    scope = funnel_stage_changes_scope.where(new_stage: all_names)
    scope = scope.where(created_at: range) if range.present?
    scope.joins('INNER JOIN conversations ON conversations.id = funnel_stage_changes.conversation_id')
         .distinct
         .pluck(:new_stage, :conversation_id, Arel.sql('conversations.ai_enabled'))
  end

  # Single point that applies the optional inbox / label / origem filters used
  # by both `Visão geral` and `Conversão`. Returns an ActiveRecord scope so
  # callers can chain `.where(...)` / `.group(...)` like they did before.
  # Filters default to OFF when the param is blank.
  def funnel_stage_changes_scope
    scope = account.funnel_stage_changes
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    scope = scope.where(conversation_id: account.conversations.tagged_with(params[:label], on: :labels).select(:id)) if params[:label].present?
    scope = scope.where(conversation_id: conversations_for_origem_scope) if params[:origem].present?
    scope
  end

  # Per-conversation attribute filter — the operator picks from a fixed
  # vocabulary in the sidebar dropdown, and the report scopes to the
  # conversations that carry that origem on their own column. The
  # ORIGEM_NONE_TOKEN maps to "no origem set" so the operator can see
  # conversations that never got attributed (auto or manual).
  def conversations_for_origem_scope
    origem = params[:origem].to_s
    scope = account.conversations
    scope = if origem == ORIGEM_NONE_TOKEN
              scope.where('conversations.origem IS NULL OR conversations.origem = ?', '')
            else
              scope.where(conversations: { origem: origem })
            end
    scope.select(:id)
  end

  # The two buckets are disjoint by construction (a conversation has a single
  # `ai_enabled` value), so the total is just `ai + manual` — no second
  # de-dup pass needed.
  def split_counts_for(group, rows)
    member_set = group[:stage_names].to_set
    ai_ids = Set.new
    manual_ids = Set.new
    rows.each do |new_stage, conv_id, ai_enabled|
      next unless member_set.include?(new_stage)

      (ai_enabled ? ai_ids : manual_ids) << conv_id
    end
    { count: ai_ids.size + manual_ids.size, count_ai: ai_ids.size, count_manual: manual_ids.size }
  end

  def build_stage_rows(groups, counts)
    empty_counts = { count: 0, count_ai: 0, count_manual: 0 }
    rows = groups.map { |group| stage_row(group, counts[group[:key]] || empty_counts) }

    rows.each_with_index do |row, idx|
      next_row = rows[idx + 1]
      next if next_row.nil?

      row[:next_stage_id] = next_row[:id]
      row[:next_stage_name] = next_row[:name]
      row[:conversion_rate] = conversion_pct(row[:count], next_row[:count])
      row[:drop_off_count] = drop_off(row[:count], next_row[:count])
      row[:conversion_exceeds_previous] = next_row[:count] > row[:count]
    end

    rows
  end

  def stage_row(group, counts)
    {
      id: group[:stage_id],
      name: group[:display_name],
      color: group[:color],
      position: group[:position],
      closed: group[:closed],
      count: counts[:count],
      count_ai: counts[:count_ai],
      count_manual: counts[:count_manual],
      next_stage_id: nil,
      next_stage_name: nil,
      conversion_rate: nil,
      drop_off_count: nil,
      conversion_exceeds_previous: false
    }
  end

  def conversion_pct(from_count, to_count)
    return nil if from_count.zero?

    ((to_count.to_f / from_count) * 100).round(2)
  end

  # Negative drop-off would be misleading (it isn't "loss" — it's an influx
  # from outside the previous stage). Clamp to zero so the UI shows "0 perdidos"
  # alongside the >100% conversion-rate flag.
  def drop_off(from_count, to_count)
    return nil if from_count.zero?

    [from_count - to_count, 0].max
  end

  # Four sales-funnel rates, all anchored on the same denominator (total
  # leads that touched the funnel in the period — same universe as the
  # first chart bar). Hidden stages still contribute to the numerators
  # (visibility is a chart concern), but they never enter the denominator
  # because `universe` is built from chart-visible stages only.
  def build_kpis(all_stages, total_leads)
    scheduling_count = distinct_count_for(scheduling_member_names(all_stages))
    confirmation_count = distinct_count_for([CONFIRMATION_STAGE_NAME])
    attendance_count = distinct_count_for([ATTENDANCE_STAGE_NAME])
    no_show_count = distinct_count_for([NO_SHOW_STAGE_NAME])

    {
      total_leads: total_leads,
      scheduling_count: scheduling_count,
      scheduling_rate: rate(scheduling_count, total_leads),
      confirmation_count: confirmation_count,
      confirmation_rate: rate(confirmation_count, total_leads),
      attendance_count: attendance_count,
      attendance_rate: rate(attendance_count, total_leads),
      no_show_count: no_show_count,
      no_show_rate: rate(no_show_count, total_leads)
    }
  end

  def scheduling_member_names(all_stages)
    all_stages.select { |stage| stage.chart_group == SCHEDULING_CHART_GROUP }.map(&:name)
  end

  def rate(count, total)
    return nil if total.zero?

    ((count.to_f / total) * 100).round(2)
  end

  def distinct_count_for(stage_names)
    return 0 if stage_names.empty?

    scope = funnel_stage_changes_scope.where(new_stage: stage_names)
    scope = scope.where(created_at: range) if range.present?
    scope.distinct.count(:conversation_id)
  end

  # Distinct conversations per loss reason in the period, sorted descending.
  # A conversation that got lost with the same reason twice still counts once
  # (mirrors how the funnel counts distinct convs per stage). Reasons with
  # zero entries in the period are omitted — the donut shouldn't render
  # empty slices.
  def build_loss_reasons_breakdown
    counts = fetch_loss_reason_counts
    return [] if counts.empty?

    total = counts.values.sum
    counts.map { |(id, name), count| loss_reason_row(id, name, count, total) }
          .sort_by { |row| -row[:count] }
  end

  def fetch_loss_reason_counts
    scope = funnel_stage_changes_scope.where.not(loss_reason_id: nil)
    scope = scope.where(created_at: range) if range.present?
    scope.joins(:loss_reason).distinct
         .group('loss_reasons.id', 'loss_reasons.name')
         .count(:conversation_id)
  end

  def loss_reason_row(id, name, count, total)
    {
      id: id,
      name: name,
      count: count,
      percentage: total.zero? ? 0 : ((count.to_f / total) * 100).round(2)
    }
  end

  # Per-ad rows for the report grid. Each row aggregates every distinct
  # conversation attributed to a Meta ad (Cloud referral's `source_id`) that
  # touched the funnel during the period, honoring the base filters + optional
  # origem. Only ads with at least one lead show up — an ad that generated a
  # click but not a conversation stays off the grid instead of muddling the
  # "top ads by leads" view. Buckets mirror the KPI strip, so a value in the
  # grid always reconciles with the aggregate above it.
  def build_campaign_breakdown(all_stages)
    rows = fetch_campaign_breakdown_rows
    return [] if rows.blank?

    spend_by_ad = meta_spend_by_ad
    by_ad = accumulate_campaign_rows(rows, all_stages)
    by_ad.values.map { |entry| campaign_row_from(entry, spend_by_ad) }.sort_by { |row| -row[:leads] }
  end

  # Meta ad spend per source_id in the current range. Mirrors the same
  # `campaign_spends` query the Marketing Analytics page uses (F3 builder).
  def meta_spend_by_ad
    scope = account.campaign_spends.where(provider: :meta, source_type: 'meta_ad')
    scope = scope.in_period(range.first.to_date, range.last.to_date) if range.present?
    scope.group(:source_id).sum(:amount_cents)
  end

  def average_ticket_cents
    (account.average_ticket.to_f * 100).round
  end

  # Pulls one row per (stage change × conversation) that carries an ad tag on
  # the conversation, joined with the ad's normalized fields so the grid can
  # render title / source_url without a second lookup.
  def fetch_campaign_breakdown_rows
    scope = funnel_stage_changes_scope
    scope = scope.where(created_at: range) if range.present?
    scope.joins('INNER JOIN conversations ON conversations.id = funnel_stage_changes.conversation_id')
         .where("conversations.additional_attributes -> 'campaign_referral' ->> 'source_id' IS NOT NULL")
         .where("conversations.additional_attributes -> 'campaign_referral' ->> 'source_id' <> ''")
         .distinct
         .pluck(
           :new_stage,
           :conversation_id,
           Arel.sql("conversations.additional_attributes -> 'campaign_referral' ->> 'source_id'"),
           Arel.sql("conversations.additional_attributes -> 'campaign_referral' ->> 'title'"),
           Arel.sql("conversations.additional_attributes -> 'campaign_referral' ->> 'source_url'")
         )
  end

  def accumulate_campaign_rows(rows, all_stages)
    scheduling_names = scheduling_member_names(all_stages).to_set
    by_ad = {}
    rows.each do |new_stage, conv_id, source_id, title, source_url|
      entry = (by_ad[source_id] ||= new_campaign_entry(source_id, title, source_url))
      entry[:lead_ids] << conv_id
      bucket = bucket_for_stage(new_stage, scheduling_names)
      entry[:bucket_ids][bucket] << conv_id if bucket
    end
    by_ad
  end

  def new_campaign_entry(source_id, title, source_url)
    {
      source_id: source_id,
      title: title,
      source_url: source_url,
      lead_ids: Set.new,
      bucket_ids: {
        qualifying: Set.new,
        scheduling: Set.new,
        confirmation: Set.new,
        attendance: Set.new
      }
    }
  end

  def bucket_for_stage(stage_name, scheduling_names)
    return :qualifying if stage_name == QUALIFYING_STAGE_NAME
    return :scheduling if scheduling_names.include?(stage_name)
    return :confirmation if stage_name == CONFIRMATION_STAGE_NAME
    return :attendance if stage_name == ATTENDANCE_STAGE_NAME

    nil
  end

  def campaign_row_from(entry, spend_by_ad) # rubocop:disable Metrics/AbcSize
    leads = entry[:lead_ids].size
    attendance_count = entry[:bucket_ids][:attendance].size
    spend_cents = spend_by_ad[entry[:source_id]] || 0
    revenue_cents = attendance_count * average_ticket_cents
    {
      source_id: entry[:source_id],
      title: entry[:title],
      source_url: entry[:source_url],
      leads: leads,
      qualifying: bucket_metric(entry[:bucket_ids][:qualifying].size, leads),
      scheduling: bucket_metric(entry[:bucket_ids][:scheduling].size, leads),
      confirmation: bucket_metric(entry[:bucket_ids][:confirmation].size, leads),
      attendance: bucket_metric(attendance_count, leads),
      spend_cents: spend_cents,
      cpl_cents: cost_per(spend_cents, leads),
      cpa_cents: cost_per(spend_cents, attendance_count),
      roas: (spend_cents.positive? && revenue_cents.positive? ? (revenue_cents.to_f / spend_cents).round(2) : nil)
    }
  end

  def cost_per(spend_cents, denominator)
    return nil if spend_cents.to_i.zero? || denominator.to_i.zero?

    (spend_cents / denominator).round
  end

  def bucket_metric(count, leads)
    { count: count, rate: leads.zero? ? nil : ((count.to_f / leads) * 100).round(1) }
  end

  def empty_kpis
    {
      total_leads: 0,
      scheduling_count: 0, scheduling_rate: nil,
      confirmation_count: 0, confirmation_rate: nil,
      attendance_count: 0, attendance_rate: nil,
      no_show_count: 0, no_show_rate: nil
    }
  end
end
# rubocop:enable Metrics/ClassLength
