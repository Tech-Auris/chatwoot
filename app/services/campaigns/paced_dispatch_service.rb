# Sends a one-off campaign's message half a cadence after it is created.
#
# The campaign already creates one contact per cadence
# (Campaigns::DispatchContactJob), so its messages are spaced by it; sending
# each one half an interval later makes creating and sending alternate — with
# a 10s cadence, a contact is created at 0s, 10s, 20s… and sent at 5s, 15s,
# 25s… — instead of both hitting the server in the same instant. The jobs
# also run on their own queue, which keeps a large campaign from sitting in
# front of the replies agents and the AI are sending in live conversations.
class Campaigns::PacedDispatchService
  QUEUE = 'campaign'.freeze

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

  def job_options
    seconds = delay
    options = { queue: QUEUE }
    options[:wait] = seconds if seconds.positive?
    options
  end

  # When the message actually leaves, which the campaign report shows.
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

  def delay
    cadence / 2
  end
end
