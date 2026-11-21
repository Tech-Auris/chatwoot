require 'administrate/field/base'

# The account's ERP: a plain select that allows none (Administrate's selectize
# hides the blank option), plus a shortcut to the account's integration with it.
class ErpSourceField < Administrate::Field::Base
  def self.searchable?
    false
  end

  # The active ERPs, plus the account's own when it was retired, so saving the
  # form never drops it.
  def options
    ErpSource.where(active: true).or(ErpSource.where(id: data)).ordered.map { |erp| [erp.name, erp.id] }
  end

  def erp_source
    resource.erp_source
  end
end
