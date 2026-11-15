# A file or text the secretary sends the patient when the AI asks for a `key`
# (in an `idioma`, or the default one when blank). Moved from the Supabase
# `resource` table; `resource_url` still points at Supabase Storage.
# == Schema Information
#
# Table name: secretary_resources
#
#  id                         :bigint           not null, primary key
#  caption                    :text
#  idioma                     :string
#  key                        :string           not null
#  resource_url               :text
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  secretary_resource_type_id :bigint           not null
#
# Indexes
#
#  index_secretary_resources_on_account_id_and_key_and_idioma  (account_id,key,idioma)
#  index_secretary_resources_on_secretary_resource_type_id     (secretary_resource_type_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (secretary_resource_type_id => secretary_resource_types.id)
#
class SecretaryResource < ApplicationRecord
  belongs_to :account
  belongs_to :secretary_resource_type

  validates :key, presence: true

  before_validation { self.idioma = idioma.presence }

  # The resource in `idioma`, falling back to the one without a language.
  def self.lookup(key:, idioma: nil)
    rows = where(key: key).order(:id)
    (idioma.present? && rows.find_by(idioma: idioma)) || rows.find_by(idioma: nil)
  end
end
