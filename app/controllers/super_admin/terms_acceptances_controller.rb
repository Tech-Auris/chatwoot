# Audit of the terms of use: who accepted which text, when, and from where.
#
# Open to every console profile on purpose — it is the record anybody may be
# asked to produce, and hiding it behind a role would mean asking the one person
# who has that role.
class SuperAdmin::TermsAcceptancesController < SuperAdmin::ApplicationController
  PER_PAGE = 25

  def index; end

  def data
    render json: { acceptances: paginated.map { |acceptance| serialize(acceptance) }, meta: pagination_meta }
  end

  # The frozen copy of what was signed. Rendered on demand rather than in the
  # listing, since it is a whole contract per row.
  def show
    acceptance = TermsAcceptance.find(params[:id])

    render json: {
      acceptance: serialize(acceptance),
      content: acceptance.terms_version.content,
      source_url: acceptance.terms_version.source_url
    }
  end

  private

  def paginated
    @paginated ||= begin
      scope = TermsAcceptance.includes(:terms_version, :account, :sales_quote).order(created_at: :desc)
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope.page(params[:page] || 1).per(PER_PAGE)
    end
  end

  def serialize(acceptance)
    {
      id: acceptance.id,
      status: acceptance.status,
      requested_at: acceptance.created_at,
      signed_at: acceptance.signed_at,
      signer_name: acceptance.signer_name,
      signer_email: acceptance.signer_email,
      signer_document: acceptance.signer_document,
      ip_address: acceptance.ip_address,
      user_agent: acceptance.user_agent,
      terms_version_id: acceptance.terms_version_id,
      content_hash: acceptance.terms_version.content_hash,
      account_name: acceptance.account&.name,
      sales_quote_id: acceptance.sales_quote_id
    }
  end

  def pagination_meta
    { current_page: paginated.current_page, total_pages: paginated.total_pages, total_count: paginated.total_count }
  end
end
