# A saved group of contacts (Marketing → Públicos), used to download the list
# and to target campaigns.
#
# * dynamic: a rule over conversations (the conversation filter's payload),
#   plus a window on when the conversation was created and an optional
#   exclusion. Its members are worked out on demand by Audiences::Resolver,
#   so a contact enters and leaves as its conversations change.
# * static: a photo. Its members are stored in audience_contacts and only
#   change by hand (CSV, freezing a dynamic audience, adding or removing).
# == Schema Information
#
# Table name: audiences
#
#  id             :bigint           not null, primary key
#  contacts_count :integer          default(0), not null
#  counted_at     :datetime
#  exclusion      :jsonb            not null
#  kind           :integer          default("dynamic"), not null
#  name           :string           not null
#  rule           :jsonb            not null
#  source         :string           default("manual"), not null
#  window         :jsonb            not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  created_by_id  :bigint
#
# Indexes
#
#  index_audiences_on_account_id  (account_id)
#
class Audience < ApplicationRecord
  # Above this a list is neither downloaded nor sent in phase 1.
  MAX_CONTACTS = 10_000
  SOURCES = %w[manual csv filter snapshot].freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :audience_contacts, dependent: :delete_all
  has_many :static_contacts, through: :audience_contacts, source: :contact
  has_many :events, class_name: 'AudienceEvent', dependent: :delete_all

  enum :kind, { dynamic: 0, static: 1 }, validate: true

  validates :name, presence: true
  validates :source, inclusion: { in: SOURCES }
  validate :window_shape

  # The contacts in the audience right now.
  def contacts
    static? ? static_contacts : Audiences::Resolver.new(account: account, rule: rule, exclusion: exclusion, window: window).contacts
  end

  def refresh_count!
    update_columns(contacts_count: contacts.count, counted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    contacts_count
  end

  # A static audience holding this one's members right now ("Congelar como
  # público fixo").
  def freeze_as!(name:, user:)
    transaction do
      frozen = account.audiences.create!(name: name, kind: :static, source: 'snapshot', created_by: user)
      frozen.add_contacts(contacts.pluck(:id))
      events.create!(kind: :snapshot, user: user, contacts_count: frozen.contacts_count)
      frozen
    end
  end

  def add_contacts(contact_ids)
    ids = account.contacts.where(id: contact_ids).pluck(:id)
    now = Time.current
    rows = ids.map { |contact_id| { audience_id: id, contact_id: contact_id, created_at: now, updated_at: now } }
    AudienceContact.insert_all(rows, unique_by: %i[audience_id contact_id]) if rows.any? # rubocop:disable Rails/SkipsModelValidations
    refresh_count!
  end

  def remove_contacts(contact_ids)
    audience_contacts.where(contact_id: contact_ids).delete_all
    refresh_count!
  end

  private

  def window_shape
    message = window_error(window.is_a?(Hash) ? window : {})
    errors.add(:window, message) if message
  end

  def window_error(shape)
    case shape['type']
    when 'all' then nil
    when 'last_days' then 'needs the number of days' unless shape['days'].to_i.positive?
    when 'range' then 'needs the start and end dates' if shape['from'].blank? || shape['to'].blank?
    else 'is invalid'
    end
  end
end
