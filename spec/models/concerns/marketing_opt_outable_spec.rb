require 'rails_helper'

RSpec.describe MarketingOptOutable do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:agent) { create(:user, account: account, name: 'Rafaela') }
  let!(:open_conversation) { create(:conversation, account: account, contact: contact, status: :open) }
  let!(:resolved_conversation) { create(:conversation, account: account, contact: contact, status: :resolved) }

  def activities(conversation)
    conversation.messages.activity.pluck(:content)
  end

  it 'turns on with its source and notes it on the conversations in progress' do
    perform_enqueued_jobs(only: Conversations::ActivityMessageJob) { contact.opt_out!(source: 'meta') }

    expect(contact.reload).to have_attributes(marketing_opt_out: true, marketing_opt_out_source: 'meta')
    expect(contact.marketing_opt_out_at).to be_present
    expect(activities(open_conversation)).to include('Marketing opt-out turned on by Meta (the patient stopped marketing messages)')
    expect(activities(resolved_conversation)).to be_empty
  end

  it 'does nothing when it is already on' do
    contact.opt_out!(source: 'meta')

    expect { contact.opt_out!(source: 'manual', user: agent) }.not_to(change { contact.reload.marketing_opt_out_source })
  end

  it 'is turned off by a person, with a note naming them' do
    contact.opt_out!(source: 'ai')

    perform_enqueued_jobs(only: Conversations::ActivityMessageJob) { contact.clear_opt_out!(user: agent) }

    expect(contact.reload).to have_attributes(marketing_opt_out: false, marketing_opt_out_at: nil, marketing_opt_out_source: nil)
    expect(activities(open_conversation).last).to start_with('Rafaela turned off the marketing opt-out')
  end

  it 'only accepts the known sources' do
    expect { contact.opt_out!(source: 'whatever') }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
