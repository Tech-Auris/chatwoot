# A copy of the terms of use as they read at a point in time.
#
# Signatures point at a version, never at the live page: the page can be edited
# at any moment, and a contract that changes after it was signed is not a
# contract anybody can audit.
class TermsVersion < ApplicationRecord
  has_many :terms_acceptances, dependent: :restrict_with_error

  validates :source_url, :content, :content_hash, :fetched_at, presence: true

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
