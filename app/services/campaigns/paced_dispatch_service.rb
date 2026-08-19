# Spaces out the messages of a one-off campaign instead of firing them all at
# once.
#
# Pacing happens at enqueue time, not by holding workers: each message is
# scheduled `cadence_seconds` after the previous one, so the rhythm holds no
# matter how many Sidekiq workers are running. The jobs also move to their own
# queue, which keeps a large campaign from sitting in front of the replies
# agents and the AI are sending in live conversations.
class Campaigns::PacedDispatchService
  QUEUE = 'campaign'.freeze
  # The counter only needs to outlive the dispatch of a single campaign.
  COUNTER_TTL = 6.hours

  pattr_initialize [:message!]

  # Returns false when the message isn't a paced campaign message, so the
  # caller can fall back to the regular immediate dispatch.
  def perform
    return false if campaign.blank? || cadence.zero?

    options = job_options
    stamp_dispatch_at(options[:wait].to_i)
    ::SendReplyJob.set(options).perform_later(message.id)
    true
  end

  private

  # `wait: 0` would still push the job through the scheduled set; the first
  # message of a campaign has nothing to wait for.
  def job_options
    seconds = delay
    options = { queue: QUEUE }
    options[:wait] = seconds if seconds.positive?
    options
  end

  # When the message actually leaves. Messages of a campaign are all created
  # in the same instant and only their dispatch is spaced out, so `created_at`
  # tells the operator nothing about the send — the report needs this instead.
  # `update_column` keeps the write out of the callback chain that is running
  # right now.
  def stamp_dispatch_at(wait_seconds)
    return unless message.persisted?

    # rubocop:disable Rails/SkipsModelValidations
    # Deliberate: this runs inside the message's own after_create_commit, so a
    # regular update would re-enter the callback chain that is still running.
    message.update_column(
      :additional_attributes,
      message.additional_attributes.merge('campaign_dispatch_at' => (Time.current + wait_seconds).to_i)
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  def campaign
    return @campaign if defined?(@campaign)

    campaign_id = message.additional_attributes&.dig('campaign_id')
    @campaign = campaign_id.present? ? Campaign.find_by(id: campaign_id) : nil
  end

  def cadence
    @cadence ||= campaign.cadence_seconds.to_i
  end

  # Position of this message within the campaign, counted atomically in Redis
  # so messages created concurrently can't land on the same slot. The first one
  # goes out immediately and each following one waits another interval.
  def delay
    position = ::Redis::Alfred.incr(counter_key)
    ::Redis::Alfred.expire(counter_key, COUNTER_TTL.to_i) if position == 1

    (position - 1) * cadence
  end

  def counter_key
    "campaign_dispatch_position:#{campaign.id}"
  end
end
