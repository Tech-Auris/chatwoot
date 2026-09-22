class AutoAssignment::AgentAssignmentService
  # Allowed agent ids: array
  # This is the list of agents from which an agent can be assigned to this conversation
  # examples: Agents with assignment capacity, Agents who are members of a team etc
  # `include_offline` opens the pool to offline members too — set by
  # team-scoped callers when the team's `auto_assign_include_offline`
  # flag is on. Defaults to `false` to preserve the online-only behavior.
  pattr_initialize [:conversation!, :allowed_agent_ids!, { include_offline: false }]

  def find_assignee
    ids = include_offline ? allowed_agent_ids&.map(&:to_s) : allowed_online_agent_ids
    round_robin_manage_service.available_agent(allowed_agent_ids: ids)
  end

  def perform
    new_assignee = find_assignee
    conversation.update!(assignee: new_assignee) if new_assignee
  end

  private

  def online_agent_ids
    online_agents = OnlineStatusTracker.get_available_users(conversation.account_id)
    online_agents.select { |_key, value| value.eql?('online') }.keys if online_agents.present?
  end

  def allowed_online_agent_ids
    # We want to perform roundrobin only over online agents
    # Hence taking an intersection of online agents and allowed member ids

    # the online user ids are string, since its from redis, allowed member ids are integer, since its from active record
    @allowed_online_agent_ids ||= online_agent_ids & allowed_agent_ids&.map(&:to_s)
  end

  def round_robin_manage_service
    @round_robin_manage_service ||= AutoAssignment::InboxRoundRobinService.new(inbox: conversation.inbox)
  end

  def round_robin_key
    format(::Redis::Alfred::ROUND_ROBIN_AGENTS, inbox_id: conversation.inbox_id)
  end
end
