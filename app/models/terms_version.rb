# A copy of the terms of use as they read at a point in time.
#
# Signatures point at a version, never at the live page: the page can be edited
# at any moment, and a contract that changes after it was signed is not a
# contract anybody can audit.
# == Schema Information
#
# Table name: terms_versions
#
#  id           :bigint           not null, primary key
#  content      :text             not null
#  content_hash :string           not null
#  fetched_at   :datetime         not null
#  source_url   :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_terms_versions_on_content_hash  (content_hash)
#
class TermsVersion < ApplicationRecord
  has_many :terms_acceptances, dependent: :restrict_with_error

  # A contract runs longer than the 20k ApplicationRecord allows every text
  # column by default, and that ceiling is lifted by declaring one here — which
  # is the escape hatch it checks for. Without this the page answered 422 on the
  # way to the payment step, since a version that cannot be saved is a contract
  # nobody can sign.
  CONTENT_LIMIT = 500_000

  validates :source_url, :content, :content_hash, :fetched_at, presence: true
  validates :content, length: { maximum: CONTENT_LIMIT }

  before_validation :assign_content_hash

  # Two fetches of an unchanged page produce the same hash, so the same version
  # is reused instead of piling up identical copies.
  def self.for_content(source_url, content)
    hash = Digest::SHA256.hexdigest(content.to_s)
    find_by(content_hash: hash) ||
      create!(source_url: source_url, content: content, content_hash: hash, fetched_at: Time.current)
  end

  private

  def assign_content_hash
    self.content_hash ||= Digest::SHA256.hexdigest(content.to_s)
  end
end
