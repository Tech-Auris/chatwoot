# The contacts of a dynamic audience, worked out from its rule.
#
# A contact belongs when ANY of its conversations meets the rule inside the
# window (on when the conversation was created), and none of its conversations
# meets the exclusion. The rule and the exclusion use the conversation
# filter's payload, so they read labels, funnel stage, loss reason, origin,
# inbox, agent and status exactly as the advanced filter does — over the whole
# account, not just the inboxes of whoever built the audience.
class Audiences::Resolver
  # The rule fields an audience accepts; anything else in a payload is left
  # out and reported back (see #ignored_conditions).
  SUPPORTED_KEYS = %w[labels funnel_stage_id loss_reason_id origem inbox_id assignee_id status].freeze

  attr_reader :ignored_conditions, :rule, :exclusion

  def initialize(account:, rule: [], exclusion: [], window: { 'type' => 'all' })
    @account = account
    @window = (window || {}).with_indifferent_access
    @ignored_conditions = []
    @rule = supported(rule)
    @exclusion = supported(exclusion)
  end

  def contacts
    @account.contacts.where(id: matching_contact_ids)
  end

  def count
    contacts.count
  end

  private

  def matching_contact_ids
    ids = within_window(conversations_for(@rule)).select(:contact_id)
    return ids if @exclusion.empty?

    ids.where.not(contact_id: conversations_for(@exclusion).select(:contact_id))
  end

  def conversations_for(conditions)
    return @account.conversations if conditions.empty?

    Audiences::ConversationQuery.new(@account, conditions).relation
  end

  def within_window(conversations)
    case @window[:type]
    when 'last_days'
      conversations.where(conversations: { created_at: @window[:days].to_i.days.ago.. })
    when 'range'
      conversations.where(conversations: { created_at: Date.parse(@window[:from]).beginning_of_day..Date.parse(@window[:to]).end_of_day })
    else
      conversations
    end
  end

  # Unsupported conditions are dropped and the chain re-closed: the last
  # condition must not carry an AND/OR pointing at nothing.
  def supported(conditions)
    kept = Array(conditions).map { |condition| condition.to_h.with_indifferent_access }.select do |condition|
      next true if SUPPORTED_KEYS.include?(condition[:attribute_key])

      @ignored_conditions << condition[:attribute_key]
      false
    end
    kept.last[:query_operator] = nil if kept.any?
    kept
  end
end
