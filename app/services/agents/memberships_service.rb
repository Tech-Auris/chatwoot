# The inboxes and teams an agent belongs to, read and set from the agent's
# side. It is only another way in: the memberships stay the inbox and team
# member records the inbox and team screens already manage, through the same
# add_members / remove_members (so auto-assignment and caches follow).
class Agents::MembershipsService
  pattr_initialize [:account!, :user!]

  def inbox_ids
    account.inboxes.joins(:inbox_members).where(inbox_members: { user_id: user.id }).pluck(:id)
  end

  def team_ids
    account.teams.joins(:team_members).where(team_members: { user_id: user.id }).pluck(:id)
  end

  # A nil list leaves that side untouched; an empty one removes the agent.
  def assign(inbox_ids: nil, team_ids: nil)
    ActiveRecord::Base.transaction do
      sync(account.inboxes, self.inbox_ids, inbox_ids) unless inbox_ids.nil?
      sync(account.teams, self.team_ids, team_ids) unless team_ids.nil?
    end
  end

  private

  def sync(records, current_ids, wanted_ids)
    wanted_ids = records.where(id: wanted_ids).pluck(:id)
    records.where(id: wanted_ids - current_ids).find_each { |record| record.add_members([user.id]) }
    records.where(id: current_ids - wanted_ids).find_each { |record| record.remove_members([user.id]) }
  end
end
