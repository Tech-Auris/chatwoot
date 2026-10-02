class V2::Reports::Conversations::MetricBuilder < V2::Reports::Conversations::BaseReportBuilder
  def summary
    {
      conversations_count: count('conversations_count'),
      incoming_messages_count: count('incoming_messages_count'),
      outgoing_messages_count: count('outgoing_messages_count'),
      avg_first_response_time: count('avg_first_response_time'),
      avg_first_response_time_median: median('avg_first_response_time'),
      avg_resolution_time: count('avg_resolution_time'),
      avg_resolution_time_median: median('avg_resolution_time'),
      resolutions_count: count('resolutions_count'),
      reply_time: count('reply_time'),
      reply_time_median: median('reply_time')
    }
  end

  def bot_summary
    {
      bot_resolutions_count: count('bot_resolutions_count'),
      bot_handoffs_count: count('bot_handoffs_count')
    }
  end

  private

  def count(metric)
    builder(metric).aggregate_value
  end

  # Time metrics: `count` returns their 95th percentile, this their median.
  def median(metric)
    builder(metric).median_value
  end

  def builder(metric)
    @builders ||= {}
    @builders[metric] ||= builder_class(metric).new(account, builder_params(metric))
  end

  def builder_params(metric)
    params.merge({ metric: metric })
  end
end
