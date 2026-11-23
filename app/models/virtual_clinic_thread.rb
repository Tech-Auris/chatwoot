# == Schema Information
#
# Table name: virtual_clinic_threads
#
#  id                :bigint           not null, primary key
#  persona           :integer          not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  parent_message_id :bigint
#  user_id           :bigint           not null
#
# Indexes
#
#  index_vc_threads_on_owner_and_persona              (account_id,user_id,persona,created_at)
#  index_virtual_clinic_threads_on_account_id         (account_id)
#  index_virtual_clinic_threads_on_parent_message_id  (parent_message_id)
#  index_virtual_clinic_threads_on_user_id            (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (parent_message_id => virtual_clinic_messages.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id)
#
class VirtualClinicThread < ApplicationRecord
  belongs_to :account
  belongs_to :user
  # Set on the talk one AI teammate had with another to answer this message.
  belongs_to :parent_message, class_name: 'VirtualClinicMessage', optional: true
  has_many :messages, -> { order(:id) }, class_name: 'VirtualClinicMessage', foreign_key: :thread_id, dependent: :destroy,
                                         inverse_of: :thread

  enum :persona, { secretary: 0, manager: 1, marketing: 2 }

  # The thread the user is talking in now for this persona, opened on demand.
  def self.current_for(account:, user:, persona:)
    where(account: account, user: user, persona: persona, parent_message_id: nil).order(:created_at).last ||
      create!(account: account, user: user, persona: persona)
  end
end
