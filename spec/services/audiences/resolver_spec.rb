require 'rails_helper'

RSpec.describe Audiences::Resolver do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:qualifying) { create(:funnel_stage, name: "qualifying_#{SecureRandom.hex(3)}") }
  let(:won) { create(:funnel_stage, name: "won_#{SecureRandom.hex(3)}") }
  let(:price) { create(:loss_reason, name: "price_#{SecureRandom.hex(3)}") }

  def conversation_for(contact, created_at: 1.day.ago, labels: [], **attributes)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, created_at: created_at, **attributes)
    conversation.update_labels(labels) if labels.any?
    conversation
  end

  def condition(key, values, operator = 'equal_to', query_operator = nil)
    { 'attribute_key' => key, 'filter_operator' => operator, 'values' => values, 'query_operator' => query_operator }
  end

  def contacts_for(rule: [], exclusion: [], window: { 'type' => 'all' })
    described_class.new(account: account, rule: rule, exclusion: exclusion, window: window).contacts
  end

  it 'takes the contacts whose conversations meet every condition' do
    both = create(:contact, account: account)
    conversation_for(both, labels: ['abc'], funnel_stage_id: qualifying.id)
    only_label = create(:contact, account: account)
    conversation_for(only_label, labels: ['abc'], funnel_stage_id: won.id)

    rule = [condition('funnel_stage_id', [qualifying.id], 'equal_to', 'AND'), condition('labels', ['abc'])]

    expect(contacts_for(rule: rule)).to contain_exactly(both)
  end

  it 'lets a contact leave when its conversation no longer meets the rule' do
    contact = create(:contact, account: account)
    conversation = conversation_for(contact, funnel_stage_id: qualifying.id)
    rule = [condition('funnel_stage_id', [qualifying.id])]
    expect(contacts_for(rule: rule)).to contain_exactly(contact)

    conversation.update!(funnel_stage_id: won.id)

    expect(contacts_for(rule: rule)).to be_empty
  end

  it 'reads the loss reason, the inbox, the agent and the status' do
    contact = create(:contact, account: account)
    agent = create(:user, account: account)
    conversation_for(contact, loss_reason_id: price.id, assignee: agent, status: :resolved)
    conversation_for(create(:contact, account: account), status: :open)

    expect(contacts_for(rule: [condition('loss_reason_id', [price.id])])).to contain_exactly(contact)
    expect(contacts_for(rule: [condition('assignee_id', [agent.id])])).to contain_exactly(contact)
    expect(contacts_for(rule: [condition('status', ['resolved'])])).to contain_exactly(contact)
    expect(contacts_for(rule: [condition('inbox_id', [inbox.id])]).count).to eq(2)
  end

  it 'counts a contact once when several of its conversations meet the rule' do
    contact = create(:contact, account: account)
    2.times { conversation_for(contact, labels: ['abc']) }

    expect(contacts_for(rule: [condition('labels', ['abc'])]).count).to eq(1)
  end

  it 'keeps only conversations created inside the window' do
    recent = create(:contact, account: account)
    conversation_for(recent, created_at: 2.days.ago)
    old = create(:contact, account: account)
    conversation_for(old, created_at: 40.days.ago)

    expect(contacts_for(window: { 'type' => 'last_days', 'days' => 30 })).to contain_exactly(recent)
    range = { 'type' => 'range', 'from' => 45.days.ago.to_date.to_s, 'to' => 35.days.ago.to_date.to_s }
    expect(contacts_for(window: range)).to contain_exactly(old)
  end

  it 'leaves out a contact when any of its conversations meets the exclusion' do
    kept = create(:contact, account: account)
    conversation_for(kept, labels: ['abc'])
    excluded = create(:contact, account: account)
    conversation_for(excluded, labels: ['abc'])
    conversation_for(excluded, labels: ['nao-perturbe'])

    expect(contacts_for(rule: [condition('labels', ['abc'])], exclusion: [condition('labels', ['nao-perturbe'])]))
      .to contain_exactly(kept)
  end

  it 'reports the conditions an audience does not accept, and drops them' do
    contact = create(:contact, account: account)
    conversation_for(contact, labels: ['abc'])
    resolver = described_class.new(account: account,
                                   rule: [condition('labels', ['abc'], 'equal_to', 'AND'), condition('browser_language', ['en'])])

    expect(resolver.contacts).to contain_exactly(contact)
    expect(resolver.ignored_conditions).to eq(['browser_language'])
  end

  it 'never reaches another account' do
    create(:conversation, account: create(:account))

    expect(contacts_for).to be_empty
  end
end
