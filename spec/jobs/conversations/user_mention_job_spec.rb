require 'rails_helper'

RSpec.describe Conversations::UserMentionJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:mentioned_user) { create(:user, account: account) }
  let(:author) { create(:user, account: account) }

  it 'creates an unseen mention when someone else mentions the user' do
    described_class.perform_now([mentioned_user.id.to_s], conversation.id, account.id, author.id)

    mention = Mention.find_by(user: mentioned_user, conversation: conversation)
    expect(mention.seen_at).to be_nil
    expect(mention.mentioned_by).to eq(author)
  end

  it 'creates a seen mention when the user mentions themselves' do
    described_class.perform_now([author.id.to_s], conversation.id, account.id, author.id)

    expect(Mention.find_by(user: author, conversation: conversation).seen_at).to be_present
  end

  it 'flags an already seen mention as unseen again on a new mention' do
    mention = create(:mention, user: mentioned_user, conversation: conversation, account: account, seen_at: 1.day.ago)

    described_class.perform_now([mentioned_user.id.to_s], conversation.id, account.id, author.id)

    expect(mention.reload.seen_at).to be_nil
  end
end
