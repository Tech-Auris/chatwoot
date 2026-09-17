class CreateCampaignSpends < ActiveRecord::Migration[7.1]
  # Cached ad spend from Meta Marketing API and Google Ads API. Fase 3
  # · F2 feeds this table daily; the Analytics report (F3) joins it
  # against `funnel_stage_changes` + `campaign_referrals` for CPL/CPA/ROAS.
  #
  # * `source_id` is the ad_id (Meta) or campaign_id (Google) — same value
  #   the incoming pipelines drop on `Conversation.campaign_referral.source_id`
  #   so the report can join without an extra mapping table.
  # * `source_type` differentiates Meta ad-level from Google campaign-level.
  # * `period_start`/`period_end` are daily by default; batching by day makes
  #   the sync idempotent (re-syncing today upserts the same row) and lets
  #   the report answer arbitrary date ranges by SUM.
  # * `amount_cents` + `currency` — money as cents to keep the SQL math
  #   integer-safe. Currency mirrors what the provider reports (Meta returns
  #   BRL for BR accounts, Google returns account default).
  def change
    create_table :campaign_spends do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.integer :provider, null: false
      t.string :source_id, null: false
      t.string :source_type, null: false
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.integer :amount_cents, null: false, default: 0
      t.string :currency, null: false
      t.datetime :last_synced_at, null: false
      t.jsonb :external_metadata, null: false, default: {}
      t.timestamps
    end

    add_index :campaign_spends,
              %i[account_id provider source_id source_type period_start period_end],
              unique: true, name: 'index_campaign_spends_unique'
    add_index :campaign_spends, %i[account_id period_start period_end]
  end
end
