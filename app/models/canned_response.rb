# == Schema Information
#
# Table name: canned_responses
#
#  id         :integer          not null, primary key
#  content    :text
#  short_code :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :integer          not null
#  inbox_id   :bigint
#
# Indexes
#
#  index_canned_responses_on_inbox_id  (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (inbox_id => inboxes.id)
#

class CannedResponse < ApplicationRecord
  validates :content, presence: true
  validates :short_code, presence: true
  validates :account, presence: true
  validates :short_code, uniqueness: { scope: :account_id }

  belongs_to :account
  # NULL means global: the response shows up in every inbox, which is how
  # every canned response behaved before scoping existed.
  belongs_to :inbox, optional: true

  validate :inbox_must_belong_to_account

  # Global responses plus the ones belonging to this inbox — what an agent
  # typing "/" inside a conversation should see.
  scope :available_for_inbox, lambda { |inbox_id|
    inbox_id.present? ? where(inbox_id: [nil, inbox_id]) : all
  }

  def inbox_must_belong_to_account
    return if inbox.blank? || inbox.account_id == account_id

    errors.add(:inbox_id, 'must belong to the same account as the canned response')
  end

  scope :order_by_search, lambda { |search|
    short_code_starts_with = sanitize_sql_array(['WHEN short_code ILIKE ? THEN 1', "#{search}%"])
    short_code_like = sanitize_sql_array(['WHEN short_code ILIKE ? THEN 0.5', "%#{search}%"])
    content_like = sanitize_sql_array(['WHEN content ILIKE ? THEN 0.2', "%#{search}%"])

    order_clause = "CASE #{short_code_starts_with} #{short_code_like} #{content_like} ELSE 0 END"

    order(Arel.sql(order_clause) => :desc)
  }
end
