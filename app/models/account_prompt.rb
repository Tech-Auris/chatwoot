# The clinic prompts the secretary uses, moved from the Supabase `cliente`
# (`ai_prompt_system_message`) and `cliente_inbox_prompt` tables and edited in
# Super Admin.
#
# Each account has one general prompt, with no inbox, and may have specific
# prompts, each for some of its inboxes. An inbox in a specific prompt uses it;
# every other inbox uses the general one. A specific prompt needs the general
# one, so the general can't be removed (or given inboxes) while there are
# specific ones.
#
# n8n (Secretária) reads it live from Postgres on every message:
#
#   select id, name, ai_prompt_system_message, inbox_ids
#   from account_prompts where account_id = $1 and ($2 = any(inbox_ids) or inbox_ids = '{}')
#   order by cardinality(inbox_ids) = 0, id limit 1
# == Schema Information
#
# Table name: account_prompts
#
#  id                       :bigint           not null, primary key
#  ai_prompt_system_message :text             not null
#  inbox_ids                :bigint           default([]), not null, is an Array
#  name                     :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#
# Indexes
#
#  index_account_prompts_on_account_id            (account_id)
#  index_account_prompts_on_inbox_ids             (inbox_ids) USING gin
#  index_account_prompts_one_general_per_account  (account_id) UNIQUE WHERE (inbox_ids = '{}'::bigint[])
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class AccountPrompt < ApplicationRecord
  belongs_to :account

  scope :general, -> { where("inbox_ids = '{}'") }
  scope :specific, -> { where("inbox_ids <> '{}'") }
  scope :ordered, -> { order(Arel.sql('cardinality(inbox_ids) > 0'), :id) }

  # Clinic prompts run past the 20k-character default of ApplicationRecord; the
  # longest one imported from Supabase has about 123k characters.
  PROMPT_MAX_LENGTH = 250_000

  validates :name, :ai_prompt_system_message, presence: true
  validates :ai_prompt_system_message, length: { maximum: PROMPT_MAX_LENGTH }
  validate :one_general_per_account, if: :general?
  validate :general_exists, unless: :general?
  validate :inboxes_belong_to_account
  validate :inboxes_not_in_another_prompt

  before_destroy :keep_general_while_specifics_exist, if: :general?

  def inbox_ids=(ids)
    super(Array(ids).compact_blank.map(&:to_i).uniq.sort)
  end

  def general?
    inbox_ids.empty?
  end

  def inboxes
    Inbox.where(id: inbox_ids).order(:id)
  end

  # The name a new prompt of the account starts with: "Geral" for the first,
  # then "Específico N".
  def self.default_name_for(account)
    return 'Geral' unless account.account_prompts.general.exists?

    "Específico #{account.account_prompts.specific.count + 1}"
  end

  private

  def siblings
    AccountPrompt.where(account_id: account_id).where.not(id: id)
  end

  def one_general_per_account
    errors.add(:inbox_ids, 'vazias: a conta já tem um prompt geral (sem caixa)') if siblings.general.exists?
  end

  def general_exists
    return if siblings.general.exists?

    errors.add(:base, 'a conta precisa de um prompt geral (sem caixa) antes dos específicos')
  end

  def inboxes_belong_to_account
    foreign = inbox_ids - Inbox.where(id: inbox_ids, account_id: account_id).pluck(:id)
    errors.add(:inbox_ids, "não são desta conta: #{foreign.join(', ')}") if foreign.any?
  end

  def inboxes_not_in_another_prompt
    taken = siblings.pluck(:inbox_ids).flatten & inbox_ids
    errors.add(:inbox_ids, "já estão em outro prompt da conta: #{taken.join(', ')}") if taken.any?
  end

  def keep_general_while_specifics_exist
    return unless siblings.specific.exists?

    errors.add(:base, 'remova os prompts específicos antes do geral')
    throw :abort
  end
end
