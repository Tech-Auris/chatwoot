# A single mapping of a Chatwoot trigger to a Meta CAPI event name and/or a
# Google Ads Enhanced Conversions event. One row per event the clinic wants
# to track — e.g., "Agendamento" firing on entry to the `Agendado` funnel
# stage, mapped to Meta `Schedule` + Google `book_appointment` label.
#
# Trigger types (Fase 2):
#   * funnel_stage_reached — `trigger_config: { "funnel_stage_id" => 42 }`
#   * label_added          — `trigger_config: { "label" => "converteu" }`
#   * automation_action    — `trigger_config: {}`
#                            (the automation action picks this event by id)
#
# `meta_event_name` and `google_event_name` are independent — a clinic can
# fire only to one provider by leaving the other blank. Empty on both makes
# the event effectively disabled even when `enabled=true`.
# == Schema Information
#
# Table name: conversion_events
#
#  id                :bigint           not null, primary key
#  enabled           :boolean          default(TRUE), not null
#  google_event_name :string
#  meta_event_name   :string
#  name              :string           not null
#  trigger_config    :jsonb            not null
#  trigger_type      :integer          not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#
# Indexes
#
#  index_conversion_events_on_account_id_and_enabled       (account_id,enabled)
#  index_conversion_events_on_account_id_and_name          (account_id,name) UNIQUE
#  index_conversion_events_on_account_id_and_trigger_type  (account_id,trigger_type)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class ConversionEvent < ApplicationRecord
  TRIGGER_TYPES = { funnel_stage_reached: 0, label_added: 1, automation_action: 2 }.freeze

  enum trigger_type: TRIGGER_TYPES

  belongs_to :account
  has_many :dispatches, class_name: 'ConversionEventDispatch', dependent: :destroy

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id }
  validate :trigger_config_matches_type
  validate :at_least_one_provider_event

  scope :enabled, -> { where(enabled: true) }
  scope :for_funnel_stage, ->(stage_id) { funnel_stage_reached.where("trigger_config ->> 'funnel_stage_id' = ?", stage_id.to_s) }
  scope :for_label, ->(label) { label_added.where("trigger_config ->> 'label' = ?", label.to_s) }

  private

  def trigger_config_matches_type
    case trigger_type
    when 'funnel_stage_reached'
      errors.add(:trigger_config, 'requires funnel_stage_id') if trigger_config['funnel_stage_id'].blank?
    when 'label_added'
      errors.add(:trigger_config, 'requires label') if trigger_config['label'].blank?
    when 'automation_action'
      # No required keys — the automation action fires the event by id.
    end
  end

  def at_least_one_provider_event
    return if meta_event_name.present? || google_event_name.present?

    errors.add(:base, 'set at least one of meta_event_name or google_event_name')
  end
end
