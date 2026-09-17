# Aggregates the reporting metrics rendered by the "Origem do lead" overview
# report. Mirrors LabelSummaryBuilder in shape (one row per bucket, same set of
# metrics) so the frontend table can reuse the same rendering, but the bucket
# key is `conversations.origem` (per-conversation column) instead of a tag name.
#
# The bucket vocabulary is the fixed set the sidebar dropdown offers plus a
# synthetic "Sem origem" row aggregating conversations with no origem attributed
# — operators need to see those leaks explicitly, not have them silently drop
# out of the totals.
class V2::Reports::OrigemSummaryBuilder
  include DateRangeHelper

  OPTIONS = [
    'Evento',
    'Facebook',
    'Google',
    'Indicação de cliente',
    'Indicação de colega',
    'Influenciador',
    'Instagram',
    'Orgânico'
  ].freeze

  # Sent back on the "Sem origem" row so the frontend can special-case its
  # label. Matches ORIGEM_NONE_TOKEN on the JS side and the filter/report
  # builders that already accept it.
  NONE_TOKEN = '__none__'.freeze

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    report_data = collect_report_data
    OPTIONS.map { |origem| build_row(origem, origem, report_data) } +
      [build_row(NONE_TOKEN, nil, report_data)]
  end

  private

  def collect_report_data
    conversation_filter = build_conversation_filter
    use_business_hours = use_business_hours?

    {
      conversation_counts: fetch_conversation_counts(conversation_filter),
      resolved_counts: fetch_resolved_counts,
      resolution_metrics: fetch_metrics(conversation_filter, 'conversation_resolved', use_business_hours),
      first_response_metrics: fetch_metrics(conversation_filter, 'first_response', use_business_hours),
      reply_metrics: fetch_metrics(conversation_filter, 'reply_time', use_business_hours)
    }
  end

  def build_row(id, origem_key, report_data)
    lookup_key = origem_key || NONE_TOKEN
    fetch = ->(bucket) { report_data[bucket][lookup_key] || 0 }
    {
      id: id,
      name: origem_key.presence || 'Sem origem',
      conversations_count: fetch.call(:conversation_counts),
      avg_resolution_time: fetch.call(:resolution_metrics),
      avg_first_response_time: fetch.call(:first_response_metrics),
      avg_reply_time: fetch.call(:reply_metrics),
      resolved_conversations_count: fetch.call(:resolved_counts)
    }
  end

  def use_business_hours?
    ActiveModel::Type::Boolean.new.cast(params[:business_hours])
  end

  def build_conversation_filter
    filter = { account_id: account.id }
    filter[:created_at] = range if range.present?
    filter
  end

  # SQL COALESCE + NULLIF collapses "no origem attributed" (nil or empty string)
  # into the NONE_TOKEN so it becomes a first-class bucket the report can group
  # on, instead of silently disappearing under GROUP BY.
  ORIGEM_EXPR = "COALESCE(NULLIF(conversations.origem, ''), '#{NONE_TOKEN}')".freeze

  def fetch_conversation_counts(conversation_filter)
    account.conversations
           .where(conversation_filter)
           .group(Arel.sql(ORIGEM_EXPR))
           .count
  end

  def fetch_resolved_counts
    filter = { name: 'conversation_resolved', account_id: account.id }
    filter[:created_at] = range if range.present?

    ReportingEvent
      .joins(:conversation)
      .where(filter)
      .group(Arel.sql(ORIGEM_EXPR))
      .count
  end

  def fetch_metrics(conversation_filter, event_name, use_business_hours)
    value_column = use_business_hours ? 'reporting_events.value_in_business_hours' : 'reporting_events.value'

    ReportingEvent
      .joins(:conversation)
      .where(conversations: conversation_filter, name: event_name)
      .group(Arel.sql(ORIGEM_EXPR))
      .pluck(Arel.sql("#{ORIGEM_EXPR} AS bucket"), Arel.sql("AVG(#{value_column}) AS avg_value"))
      .then { |rows| rows.to_h.transform_values(&:to_f) }
  end
end
