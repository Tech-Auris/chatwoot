# Fans a single super_admin decision out into the rows the dashboard needs:
# the `TermsAcceptanceRequest` (the campaign itself), one pending
# `TermsAcceptance` per required manager per account, and the
# `OperationsNotification` that opens the modal at each manager's next login.
#
# All three go in one transaction — a partial fanout would leave the report
# claiming a campaign that no manager can actually sign.
class Terms::CreateCampaignService
  Result = Struct.new(:campaign, :notification, :acceptance_count, keyword_init: true)

  def initialize(super_admin:, terms_version:, document_date:, deadline_at:, kind: :update, # rubocop:disable Metrics/ParameterLists
                 required_signers_by_account: {})
    @super_admin = super_admin
    @terms_version = terms_version
    @document_date = document_date
    @deadline_at = deadline_at
    @kind = kind
    @required_signers_by_account = required_signers_by_account
  end

  def perform
    ApplicationRecord.transaction do
      campaign = TermsAcceptanceRequest.create!(
        terms_version: @terms_version,
        created_by: @super_admin,
        document_date: @document_date,
        deadline_at: @deadline_at,
        kind: @kind
      )

      count = build_acceptances(campaign)
      notification = build_notification(campaign)

      Result.new(campaign: campaign, notification: notification, acceptance_count: count)
    end
  end

  private

  def build_acceptances(campaign)
    count = 0
    @required_signers_by_account.each do |account_id, account_user_ids|
      account_user_ids.each do |account_user_id|
        campaign.terms_acceptances.create!(
          terms_version: @terms_version,
          account_id: account_id,
          account_user_id: account_user_id,
          kind: @kind,
          status: :pending,
          required: true,
          deadline_at: @deadline_at
        )
        count += 1
      end
    end
    count
  end

  # Scoped to only the accounts the campaign actually asks something of, so
  # a super_admin who leaves some accounts out of the roster does not open
  # the modal on managers who have no acceptance to produce.
  def build_notification(campaign)
    account_ids = @required_signers_by_account.keys.map(&:to_i).uniq
    OperationsNotification.create!(
      title: 'Novos termos de uso',
      body: 'Assine a nova versão dos termos de uso para continuar.',
      severity: :emergency,
      scope_type: account_ids.empty? ? :all_accounts : :accounts,
      account_ids: account_ids,
      audience_type: :managers,
      trigger_kind: :on_login,
      published_at: Time.current,
      expires_at: @deadline_at,
      created_by: @super_admin,
      subject: campaign
    )
  end
end
