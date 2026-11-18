# The clinic prompt the secretary uses on some of the account's inboxes, for
# accounts whose own `ai_prompt_system_message` is empty. Moved from the
# Supabase `cliente_inbox_prompt` table and edited in Super Admin, from the
# account page.
#
# n8n's `Buscar prompt por inbox` (Secretária v3.3) reads it live from Postgres
# on every message:
#
#   select id, $1::bigint as cliente_id, ai_prompt_system_message, inbox_ids as inbox_id_arr
#   from inbox_prompts where account_id = $2 and $3 = any(inbox_ids) order by id limit 2
# == Schema Information
#
# Table name: inbox_prompts
#
#  id                       :bigint           not null, primary key
#  ai_prompt_system_message :text             not null
#  inbox_ids                :bigint           default([]), not null, is an Array
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#
# Indexes
#
#  index_inbox_prompts_on_account_id  (account_id)
#  index_inbox_prompts_on_inbox_ids   (inbox_ids) USING gin
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class InboxPrompt < ApplicationRecord
  belongs_to :account

  validates :ai_prompt_system_message, presence: true
  validates :inbox_ids, presence: true
  validate :inboxes_belong_to_account
  validate :inboxes_not_in_another_prompt

  def inbox_ids=(ids)
    super(Array(ids).compact_blank.map(&:to_i).uniq.sort)
  end

  def inboxes
    Inbox.where(id: inbox_ids).order(:id)
  end

  private

  def inboxes_belong_to_account
    foreign = inbox_ids - Inbox.where(id: inbox_ids, account_id: account_id).pluck(:id)
    errors.add(:inbox_ids, "não são desta conta: #{foreign.join(', ')}") if foreign.any?
  end

  def inboxes_not_in_another_prompt
    taken = InboxPrompt.where(account_id: account_id).where.not(id: id).pluck(:inbox_ids).flatten & inbox_ids
    errors.add(:inbox_ids, "já estão em outro prompt da conta: #{taken.join(', ')}") if taken.any?
  end
end
