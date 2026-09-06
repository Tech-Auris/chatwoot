# Flips a re-signature campaign to `expired` at its deadline and cuts the
# sessions of everybody in the accounts that did not finish signing.
#
# Scheduled by `Terms::CreateCampaignService` with `set(wait_until: deadline_at)`;
# a manual `.perform_now` on a late runner produces the same effect, so a
# missed tick (worker down when the deadline lands) can be recovered by hand.
class Terms::ExpireCampaignJob < ApplicationJob
  queue_as :low

  def perform(campaign_id)
    campaign = TermsAcceptanceRequest.find_by(id: campaign_id)
    return if campaign.blank?
    # Idempotent — a super_admin who closed the campaign early, or a job that
    # ran twice, must not double-revoke sessions.
    return unless campaign.status_open?

    campaign.update!(status: :expired)
    revoke_sessions_for(campaign)
  end

  private

  # Revokes every user (agent + manager) of any account that still has a
  # pending required signature on this campaign. The manager can re-login
  # right away — the modal opens and lets them sign — and the account
  # unlocks on that signature; agents stay refused until then.
  def revoke_sessions_for(campaign)
    account_ids = campaign.terms_acceptances.status_pending.where(required: true).pluck(:account_id).uniq
    return if account_ids.empty?

    # `DISTINCT users.*` fails on the JSON columns (no equality operator);
    # pluck the ids first, then re-fetch the actual rows to save.
    user_ids = AccountUser.where(account_id: account_ids).distinct.pluck(:user_id)
    User.where(id: user_ids).find_each do |user|
      user.tokens = {}
      user.save!
      user.user_sessions.destroy_all
    end
  end
end
