# A setting the n8n flows read through `GetConfigurations`, moved from the
# Supabase `configuration` table with the same ids (flows hardcode some, e.g.
# 1 = GDrive.RootFolderId in "Fim contratação - Cadastro Geral"). Each account
# may override `default_value` (see AccountAurisConfig).
#
# Keys in use: GDrive.RootFolderId, GDrive.PollIntervalMinutes,
# GDrive.LastCheckpointUtc (UpdatingClientData's RAG polling),
# ClientUpdt.LockStartUtc (UpdatingClientData's global lock, kept in
# `default_value`), Secretaria.BounceSeconds (the Secretárias' fallback
# bounce), Billing.MaxId, Agenda.HorariosLivres.AddMonth.
#
# n8n reads it live from Postgres (same output as the Supabase version):
#
#   select c.id::text as "ConfigId", c.config_key as "ConfigKey", c.value_type as "ValueType",
#          c.default_value as "DefaultValue", c.description as "Description",
#          a.value is not null as "HasClientValue", a.value as client_value, a.id::int as client_config_id
#   from auris_configs c
#   left join account_auris_configs a on a.auris_config_id = c.id and a.account_id = $1
#   where coalesce($2, '') = '' or c.config_key = $2
#   order by c.id
# == Schema Information
#
# Table name: auris_configs
#
#  id            :bigint           not null, primary key
#  config_key    :string           not null
#  default_value :text
#  description   :text
#  value_type    :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_auris_configs_on_config_key  (config_key) UNIQUE
#
class AurisConfig < ApplicationRecord
  has_many :account_auris_configs, dependent: :delete_all

  validates :config_key, presence: true, uniqueness: true
  validates :value_type, presence: true
end
