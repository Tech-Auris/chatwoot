# A situation the secretary handles in a specific way: the prompt lists its
# `situacao` and `gatilho`, and the AI fetches the `instrucao` by `name` through
# n8n's `12. Special Scenario Retriever`. Moved from the Supabase
# `special_scenarios` table and edited in Super Admin.
#
# n8n reads them from the Redis key `cache_supabase_special_scenarios:{account_id}`;
# every change rewrites it (see SecretarySpecialScenarios::RefreshCacheJob).
# == Schema Information
#
# Table name: secretary_special_scenarios
#
#  id         :bigint           not null, primary key
#  gatilho    :text
#  instrucao  :text
#  name       :string           not null
#  situacao   :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_secretary_special_scenarios_on_account_id_and_name  (account_id,name)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class SecretarySpecialScenario < ApplicationRecord
  belongs_to :account

  validates :name, presence: true

  after_commit :refresh_cache

  # The value n8n keeps in `cache_supabase_special_scenarios:{account_id}`, same
  # shape and key order as the n8n `Cache special_scenarios cliente` node.
  def self.cache_payload(account_id)
    where(account_id: account_id).order(:id).map do |scenario|
      { cliente_id: account_id, name: scenario.name, situacao: scenario.situacao,
        gatilho: scenario.gatilho, instrucao: scenario.instrucao }
    end
  end

  private

  def refresh_cache
    [account_id, account_id_previously_was].compact.uniq.each do |id|
      SecretarySpecialScenarios::RefreshCacheJob.perform_later(id)
    end
  end
end
