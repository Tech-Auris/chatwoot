# Super Admin → Commercial → Contrato: the switch for the contract step, the
# automatic signature for Auris and the contract template with its versions.
class SuperAdmin::Commercial::ContractsController < SuperAdmin::ApplicationController
  def show; end

  def data
    render json: payload
  end

  def settings
    Sales::ContractSettings.update!(enabled: params[:enabled], auto_sign: params[:auto_sign])
    render json: payload
  end

  def templates
    SalesContractTemplate.publish!(content: params.require(:content), created_by_name: current_super_admin.name)
    render json: payload
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def template_version
    template = SalesContractTemplate.find_by!(version: params[:version])
    render json: { version: template.version, content: template.content }
  end

  # PDF of what is in the editor right now, filled with sample data.
  def preview
    person_type = params[:person_type] == 'pf' ? 'pf' : 'pj'
    html = Sales::ContractTemplateRenderer.new(content: params.require(:content), variables: Sales::ContractVariables.sample(person_type),
                                               person_type: person_type).render
    send_data Sales::ContractPdfService.new(html).to_pdf, type: 'application/pdf', disposition: 'inline',
                                                          filename: "contrato-exemplo-#{person_type}.pdf"
  end

  # Who signs for Auris: the Autentique token's user.
  def signer
    me = Integrations::Autentique::Client.new.me
    render json: { name: me['name'], email: me['email'] }
  rescue Integrations::Autentique::Client::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def payload
    current = SalesContractTemplate.current
    {
      enabled: Sales::ContractSettings.enabled?,
      auto_sign: Sales::ContractSettings.auto_sign?,
      autentique_configured: Integrations::Autentique::Client.new.configured?,
      template: current.slice(:version, :content, :created_by_name, :created_at),
      versions: SalesContractTemplate.latest_first.map { |template| template.slice(:version, :created_by_name, :created_at) },
      fields: Sales::ContractVariables::FIELDS
    }
  end
end
