# The conversations of the whole account that meet a filter payload, built
# with the advanced conversation filter's own query (operators, labels, funnel
# fields and contact-backed attributes alike) but without its per-user inbox
# restriction and without paging: an audience belongs to the account.
class Audiences::ConversationQuery < Conversations::FilterService
  def initialize(account, conditions)
    super({ payload: conditions }, nil, account)
  end

  def relation
    validate_query_operator
    query_builder(@filters['conversations'])
  end

  def base_relation
    conversations = @account.conversations
    references_contact_attributes? ? conversations.left_outer_joins(:contact) : conversations
  end
end
