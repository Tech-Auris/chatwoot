# The kinds of file the secretary sends (1 image, 2 pdf, 3 video, 4 audio,
# 5 macro, 6 doc). Seeded by the migration with the ids n8n branches on; not
# editable.
# == Schema Information
#
# Table name: secretary_resource_types
#
#  id          :bigint           not null, primary key
#  description :string           not null
#
class SecretaryResourceType < ApplicationRecord
  has_many :secretary_resources, dependent: :restrict_with_error
end
