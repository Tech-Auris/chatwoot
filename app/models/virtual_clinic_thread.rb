class VirtualClinicThread < ApplicationRecord
  belongs_to :account
  belongs_to :user
  has_many :messages, -> { order(:id) }, class_name: 'VirtualClinicMessage', foreign_key: :thread_id, dependent: :destroy,
                                         inverse_of: :thread

  enum :persona, { secretary: 0, manager: 1 }

  # The thread the user is talking in now for this persona, opened on demand.
  def self.current_for(account:, user:, persona:)
    where(account: account, user: user, persona: persona).order(:created_at).last ||
      create!(account: account, user: user, persona: persona)
  end
end
