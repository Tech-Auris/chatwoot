# Read by n8n's `Resource` tool: the resource the AI asked for, in the
# conversation's language or the default one. Managed in Super Admin.
class Api::V1::Accounts::SecretaryResourcesController < Api::V1::Accounts::BaseController
  def lookup
    @secretary_resource = Current.account.secretary_resources.lookup(key: params.require(:key), idioma: params[:idioma])
    head :not_found if @secretary_resource.nil?
  end
end
