class Api::V1::Accounts::Contacts::ConversationsController < Api::V1::Accounts::Contacts::BaseController
  PER_PAGE = 20

  # The contact's conversations, newest created first, PER_PAGE at a time.
  # Ordered by creation so a campaign, follow-up or reminder landing on an old
  # conversation doesn't move it around the list.
  def index
    conversations = Current.account.conversations.includes(
      :assignee, :contact, :inbox, :taggings
    ).where(contact_id: @contact.id)

    conversations = Conversations::PermissionFilterService.new(
      conversations,
      Current.user,
      Current.account
    ).perform

    page = conversations.order(created_at: :desc, id: :desc).offset((current_page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @has_more = page.size > PER_PAGE
    @conversations = page.first(PER_PAGE)
  end

  private

  def current_page
    [params[:page].to_i, 1].max
  end
end
