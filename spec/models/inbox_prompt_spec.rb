require 'rails_helper'

RSpec.describe InboxPrompt do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }

  it 'keeps the inbox ids unique, sorted and without blanks' do
    prompt = described_class.new(account: account, inbox_ids: ['', other_inbox.id.to_s, inbox.id.to_s, inbox.id.to_s])

    expect(prompt.inbox_ids).to eq([inbox.id, other_inbox.id].sort)
  end

  it 'requires at least one inbox' do
    prompt = build(:inbox_prompt, account: account, inbox_ids: [])

    expect(prompt).not_to be_valid
    expect(prompt.errors[:inbox_ids]).to be_present
  end

  it 'rejects an inbox from another account' do
    foreign = create(:inbox)
    prompt = build(:inbox_prompt, account: account, inbox_ids: [inbox.id, foreign.id])

    expect(prompt).not_to be_valid
    expect(prompt.errors[:inbox_ids].join).to include(foreign.id.to_s)
  end

  it 'rejects an inbox another prompt of the account already has' do
    create(:inbox_prompt, account: account, inbox_ids: [inbox.id])
    prompt = build(:inbox_prompt, account: account, inbox_ids: [inbox.id, other_inbox.id])

    expect(prompt).not_to be_valid
    expect(prompt.errors[:inbox_ids].join).to include(inbox.id.to_s)
  end

  it 'saves an existing prompt with its own inboxes' do
    prompt = create(:inbox_prompt, account: account, inbox_ids: [inbox.id])

    expect(prompt.update(ai_prompt_system_message: 'Novo texto')).to be(true)
  end

  it 'is found by the query n8n runs' do
    prompt = create(:inbox_prompt, account: account, inbox_ids: [inbox.id, other_inbox.id])
    sql = <<~SQL.squish
      select id, $1::bigint as cliente_id, ai_prompt_system_message, inbox_ids as inbox_id_arr
      from inbox_prompts where account_id = $2 and $3 = any(inbox_ids) order by id limit 2
    SQL

    result = ActiveRecord::Base.connection.exec_query(sql, 'n8n', [150, account.id, other_inbox.id])

    expect(result.columns).to eq(%w[id cliente_id ai_prompt_system_message inbox_id_arr])
    expect(result.cast_values).to eq([[prompt.id, 150, prompt.ai_prompt_system_message, prompt.inbox_ids]])
  end
end
