# Super admin cockpit for a re-signature campaign: preview the current
# marketing page, pick which managers per account are required to sign, set a
# deadline, and cut the campaign. Every action here targets `kind: update` —
# `signature` rides the sales-checkout flow and never touches this controller.
class SuperAdmin::TermsAcceptanceRequestsController < SuperAdmin::ApplicationController
  PER_PAGE = 25

  def index; end

  def data
    render json: {
      requests: paginated.map { |c| serialize_campaign(c) },
      meta: pagination_meta
    }
  end

  def show
    @campaign = TermsAcceptanceRequest.find(params[:id])
  end

  def new; end

  # Live fetch of the marketing page so the wizard's step 1 shows exactly
  # what the manager will be asked to sign. Returns the persisted version
  # (dedup'd by hash — a second fetch of unchanged wording reuses the row)
  # so step 3 can post `terms_version_id` back.
  def preview
    version = Sales::TermsFetcherService.new(url: params[:url].presence).perform
    render json: serialize_version(version)
  rescue Sales::TermsFetcherService::Unavailable => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Feeds step 3 with `[{account_id, account_name, managers: [{id, name, email}]}]`.
  # Only accounts that HAVE at least one manager appear — a campaign with no
  # required signer is meaningless.
  def manager_roster
    roster = AccountUser.where(role: :manager).includes(:account, :user).order('accounts.name, users.name')
    grouped = roster.group_by(&:account_id).map do |account_id, account_users|
      account = account_users.first.account
      { account_id: account_id, account_name: account.name,
        managers: account_users.map do |au|
          { account_user_id: au.id, user_id: au.user_id,
            name: au.user.available_name, email: au.user.email }
        end }
    end
    render json: { accounts: grouped }
  end

  def create
    payload = campaign_params
    version = TermsVersion.find(payload[:terms_version_id])
    result = Terms::CreateCampaignService.new(
      super_admin: current_super_admin,
      terms_version: version,
      document_date: payload[:document_date],
      deadline_at: payload[:deadline_at],
      required_signers_by_account: parse_required_signers(payload[:required_signers_by_account])
    ).perform

    render json: { id: result.campaign.id, acceptance_count: result.acceptance_count }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  # Drill-down JSON for the show page: per-account rollup of who signed and who did not.
  def report
    campaign = TermsAcceptanceRequest.find(params[:id])
    acceptances = campaign.terms_acceptances.includes(account: :account_users, account_user: :user).order('accounts.name')
    grouped = acceptances.group_by(&:account_id).map do |account_id, rows|
      account = rows.first.account
      { account_id: account_id, account_name: account.name, signers: rows.map { |r| serialize_signer(r) } }
    end
    render json: {
      campaign: serialize_campaign(campaign, include_version_url: true),
      accounts: grouped
    }
  end

  private

  def paginated
    @paginated ||= TermsAcceptanceRequest
                   .includes(:terms_version, :created_by)
                   .order(created_at: :desc)
                   .page(params[:page] || 1).per(PER_PAGE)
  end

  def pagination_meta
    { current_page: paginated.current_page, total_pages: paginated.total_pages, total_count: paginated.total_count }
  end

  def campaign_params
    params.require(:campaign).permit(
      :terms_version_id, :document_date, :deadline_at,
      required_signers_by_account: {}
    )
  end

  # `permit(required_signers_by_account: {})` returns an
  # `ActionController::Parameters`; unwrap it before rebuilding the hash
  # so `each_with_object` works. The payload comes in as
  # `{ "42" => ["7", "9"] }` and we want integer keys and integer values
  # so the FK writes are unambiguous.
  def parse_required_signers(raw)
    return {} if raw.blank?

    raw.to_unsafe_h.each_with_object({}) do |(account_id, ids), acc|
      account_key = account_id.to_i
      acc[account_key] = Array(ids).map(&:to_i).uniq if account_key.positive?
    end
  end

  def serialize_campaign(campaign, include_version_url: false)
    signed = campaign.terms_acceptances.status_signed.count
    total = campaign.terms_acceptances.count
    base = {
      id: campaign.id,
      kind: campaign.kind,
      status: campaign.status,
      document_date: campaign.document_date,
      deadline_at: campaign.deadline_at,
      created_at: campaign.created_at,
      created_by: campaign.created_by&.available_name.presence || campaign.created_by&.email,
      signed_count: signed,
      total_count: total,
      terms_version_id: campaign.terms_version_id,
      content_hash: campaign.terms_version.content_hash
    }
    base[:source_url] = campaign.terms_version.source_url if include_version_url
    base
  end

  def serialize_version(version)
    {
      id: version.id,
      source_url: version.source_url,
      content: version.content,
      content_hash: version.content_hash,
      document_date: version.document_date,
      fetched_at: version.fetched_at
    }
  end

  def serialize_signer(row)
    {
      acceptance_id: row.id,
      account_user_id: row.account_user_id,
      user_name: row.account_user&.user&.available_name,
      user_email: row.account_user&.user&.email,
      required: row.required,
      status: row.status,
      signed_at: row.signed_at,
      signer_name: row.signer_name,
      signer_email: row.signer_email,
      ip_address: row.ip_address
    }
  end
end
