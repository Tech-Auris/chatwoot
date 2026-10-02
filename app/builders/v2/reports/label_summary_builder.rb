class V2::Reports::LabelSummaryBuilder < V2::Reports::BaseSummaryBuilder
  attr_reader :account, :params

  # rubocop:disable Lint/MissingSuper
  # the parent class has no initialize
  def initialize(account:, params:)
    @account = account
    @params = params

    timezone_offset = (params[:timezone_offset] || 0).to_f
    @timezone = ActiveSupport::TimeZone[timezone_offset]&.name
  end
  # rubocop:enable Lint/MissingSuper

  def build
    labels = account.labels.to_a
    return [] if labels.empty?

    report_data = collect_report_data
    labels.map { |label| build_label_report(label, report_data) }
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

  def build_label_report(label, report_data)
    {
      id: label.id,
      name: label.title,
      conversations_count: report_data[:conversation_counts][label.title] || 0,
      resolved_conversations_count: report_data[:resolved_counts][label.title] || 0
    }.merge(time_metrics(report_data, label.title))
  end

  # 95th percentile of each time metric plus its median (shown in the hint).
  def time_metrics(report_data, key)
    { avg_resolution_time: :resolution_metrics, avg_first_response_time: :first_response_metrics,
      avg_reply_time: :reply_metrics }.each_with_object({}) do |(field, bucket), result|
      values = report_data[bucket][key] || {}
      result[field] = values[:p95] || 0
      result[:"#{field}_median"] = values[:median] || 0
    end
  end

  def use_business_hours?
    ActiveModel::Type::Boolean.new.cast(params[:business_hours])
  end

  def build_conversation_filter
    conversation_filter = { account_id: account.id }
    conversation_filter[:created_at] = range if range.present?

    conversation_filter
  end

  def fetch_conversation_counts(conversation_filter)
    fetch_counts(conversation_filter)
  end

  def fetch_resolved_counts
    # Count resolution events, not conversations currently in resolved status
    # Filter by reporting_event.created_at, not conversation.created_at
    reporting_event_filter = { name: 'conversation_resolved', account_id: account.id }
    reporting_event_filter[:created_at] = range if range.present?

    ReportingEvent
      .joins(conversation: { taggings: :tag })
      .where(
        reporting_event_filter.merge(
          taggings: { taggable_type: 'Conversation', context: 'labels' }
        )
      )
      .group('tags.name')
      .count
  end

  def fetch_counts(conversation_filter)
    ActsAsTaggableOn::Tagging
      .joins('INNER JOIN conversations ON taggings.taggable_id = conversations.id')
      .joins('INNER JOIN tags ON taggings.tag_id = tags.id')
      .where(
        taggable_type: 'Conversation',
        context: 'labels',
        conversations: conversation_filter
      )
      .select('tags.name, COUNT(taggings.*) AS count')
      .group('tags.name')
      .each_with_object({}) { |record, hash| hash[record.name] = record.count }
  end

  def fetch_metrics(conversation_filter, event_name, use_business_hours)
    ReportingEvent
      .joins(conversation: { taggings: :tag })
      .where(
        conversations: conversation_filter,
        name: event_name,
        taggings: { taggable_type: 'Conversation', context: 'labels' }
      )
      .group('tags.name')
      .order('tags.name')
      .select('tags.name', *percentile_selects(use_business_hours))
      .each_with_object({}) { |record, hash| hash[record.name] = { p95: record.p95_value.to_f, median: record.median_value.to_f } }
  end

  def percentile_selects(use_business_hours)
    column = use_business_hours ? 'reporting_events.value_in_business_hours' : 'reporting_events.value'
    ["#{Reports::TimePercentiles.sql(Reports::TimePercentiles::P95, column)} as p95_value",
     "#{Reports::TimePercentiles.sql(Reports::TimePercentiles::MEDIAN, column)} as median_value"]
  end
end
