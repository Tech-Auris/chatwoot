require 'administrate/field/base'

# The fields an ERP's integration holds (`erp_sources.fields`), edited as rows;
# a row with a blank key is dropped, so the blank rows at the end add new ones.
class ErpFieldsField < Administrate::Field::Base
  BLANK_ROWS = 3

  def self.permitted_attribute(attr, _options = nil)
    { attr => %i[key label type secret] }
  end

  def rows
    data.to_a + Array.new(BLANK_ROWS) { { 'type' => 'text', 'secret' => false } }
  end
end
