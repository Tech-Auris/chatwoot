# An account's value for an AurisConfig, moved from the Supabase
# `configuration_client` table. n8n also writes it: UpdatingClientData saves
# each account's GDrive.LastCheckpointUtc, and "Fim contratação - Cadastro
# Geral" creates the GDrive.RootFolderId of a new client.
# == Schema Information
#
# Table name: account_auris_configs
#
#  id              :bigint           not null, primary key
#  value           :text
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  auris_config_id :bigint           not null
#
# Indexes
#
#  index_account_auris_configs_on_account_id_and_auris_config_id  (account_id,auris_config_id) UNIQUE
#  index_account_auris_configs_on_auris_config_id                 (auris_config_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (auris_config_id => auris_configs.id)
#
class AccountAurisConfig < ApplicationRecord
  belongs_to :account
  belongs_to :auris_config

  validates :auris_config_id, uniqueness: { scope: :account_id }
end
