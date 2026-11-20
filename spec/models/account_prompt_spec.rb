require 'rails_helper'

RSpec.describe AccountPrompt do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }

  it 'accepts clinic prompts longer than the 20k-character default' do
    prompt = described_class.create!(account: account, name: 'Geral', ai_prompt_system_message: 'a' * 150_000)

    expect(prompt.reload.ai_prompt_system_message.length).to eq(150_000)
    expect(described_class.new(account: account, name: 'Geral', ai_prompt_system_message: 'a' * 250_001)).not_to be_valid
  end

  it 'accepts base blocks longer than the 20k-character default' do
    expect(SecretaryPrompt.create!(core_behavior: 'a' * 30_000).reload.core_behavior.length).to eq(30_000)
  end

  it 'keeps the inbox ids unique, sorted and without blanks' do
    prompt = described_class.new(account: account, inbox_ids: ['', other_inbox.id.to_s, inbox.id.to_s, inbox.id.to_s])

    expect(prompt.inbox_ids).to eq([inbox.id, other_inbox.id].sort)
  end

  it 'allows one general prompt (no inbox) per account' do
    create(:account_prompt, account: account)
    prompt = build(:account_prompt, account: account, name: 'Outro geral')

    expect(prompt).not_to be_valid
    expect(prompt.errors[:inbox_ids]).to be_present
  end

  it 'refuses a specific prompt when the account has no general one' do
    prompt = described_class.new(account: account, name: 'Específico 1', ai_prompt_system_message: 'Texto', inbox_ids: [inbox.id])

    expect(prompt).not_to be_valid
    expect(prompt.errors[:base].join).to include('prompt geral')
  end

  it 'refuses giving inboxes to the general prompt, which would leave the specific ones without it' do
    general = create(:account_prompt, account: account)
    create(:account_prompt, :specific, account: account, inbox_ids: [inbox.id])

    expect(general.update(inbox_ids: [other_inbox.id])).to be(false)
  end

  it 'refuses removing the general prompt while there are specific ones' do
    general = create(:account_prompt, account: account)
    create(:account_prompt, :specific, account: account, inbox_ids: [inbox.id])

    expect(general.destroy).to be(false)
    expect(general.errors[:base].join).to include('específicos')
  end

  it 'removes the general prompt when it is the only one' do
    general = create(:account_prompt, account: account)

    expect(general.destroy).to be_truthy
  end

  it 'rejects an inbox from another account' do
    foreign = create(:inbox)
    prompt = build(:account_prompt, :specific, account: account, inbox_ids: [inbox.id, foreign.id])

    expect(prompt).not_to be_valid
    expect(prompt.errors[:inbox_ids].join).to include(foreign.id.to_s)
  end

  it 'rejects an inbox another prompt of the account already has' do
    create(:account_prompt, :specific, account: account, inbox_ids: [inbox.id])
    prompt = build(:account_prompt, :specific, account: account, inbox_ids: [inbox.id, other_inbox.id])

    expect(prompt).not_to be_valid
    expect(prompt.errors[:inbox_ids].join).to include(inbox.id.to_s)
  end

  it 'saves an existing specific prompt with its own inboxes' do
    prompt = create(:account_prompt, :specific, account: account, inbox_ids: [inbox.id])

    expect(prompt.update(ai_prompt_system_message: 'Novo texto')).to be(true)
  end

  it 'names a new prompt Geral, then Específico N' do
    expect(described_class.default_name_for(account)).to eq('Geral')

    create(:account_prompt, :specific, account: account)

    expect(described_class.default_name_for(account)).to eq('Específico 2')
  end

  describe 'the query n8n runs' do
    let(:sql) do
      <<~SQL.squish
        select id, name, ai_prompt_system_message, inbox_ids
        from account_prompts where account_id = $1 and ($2 = any(inbox_ids) or inbox_ids = '{}')
        order by cardinality(inbox_ids) = 0, id limit 1
      SQL
    end
    let!(:general) { create(:account_prompt, account: account) }
    let!(:specific) { create(:account_prompt, :specific, account: account, inbox_ids: [inbox.id]) }

    def prompt_for(inbox_id)
      ActiveRecord::Base.connection.exec_query(sql, 'n8n', [account.id, inbox_id]).cast_values
    end

    it 'returns the specific prompt of the inbox' do
      expect(prompt_for(inbox.id)).to eq([[specific.id, specific.name, specific.ai_prompt_system_message, [inbox.id]]])
    end

    it 'returns the general prompt for an inbox in no specific prompt' do
      expect(prompt_for(other_inbox.id)).to eq([[general.id, 'Geral', general.ai_prompt_system_message, []]])
    end
  end
end
