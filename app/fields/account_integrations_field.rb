require 'administrate/field/base'

# The account's ERP integrations on the Super Admin account page, the one of the
# account's ERP first (the one n8n uses), each with a link to edit it, plus a
# link to add one for this account.
class AccountIntegrationsField < Administrate::Field::Base
  def integrations
    data.includes(:erp_source).sort_by { |integration| [integration.active? ? 0 : 1, integration.erp_source_id] }
  end
end
