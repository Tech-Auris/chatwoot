require 'rails_helper'

RSpec.describe AiDisableable do
  let(:account) { create(:account, ai_status_uses_attribute: true, locale: 'pt_BR') }
  let(:contact) { create(:contact, account: account) }
  let(:agent) { create(:user, account: account, name: 'Ana') }
  let!(:open_conversation) { create(:conversation, account: account, contact: contact, status: :open) }
  let!(:resolved_conversation) { create(:conversation, account: account, contact: contact, status: :resolved) }

  before { Current.user = agent }

  after { Current.reset }

  def activities(conversation)
    conversation.messages.activity.pluck(:content)
  end

  it 'turns off with who and when, and turns the AI off in the conversations in progress' do
    perform_enqueued_jobs(only: Conversations::ActivityMessageJob) { contact.disable_ai!(agent) }

    expect(contact.reload).to have_attributes(ai_disabled: true, ai_disabled_by: agent)
    expect(contact.ai_disabled_at).to be_present
    expect(open_conversation.reload.ai_enabled).to be(false)
    expect(resolved_conversation.reload.ai_enabled).to be(true)
    expect(activities(open_conversation)).to include('Ana desligou a IA para este contato')
  end

  it 'turns back on for the next messages only, leaving the conversations in progress off' do
    contact.disable_ai!(agent)

    perform_enqueued_jobs(only: Conversations::ActivityMessageJob) { contact.enable_ai!(agent) }

    expect(contact.reload).to have_attributes(ai_disabled: false, ai_disabled_at: nil, ai_disabled_by: nil)
    expect(open_conversation.reload.ai_enabled).to be(false)
    expect(activities(open_conversation)).to include('Ana religou a IA para este contato: vale para as próximas mensagens')
  end
end
