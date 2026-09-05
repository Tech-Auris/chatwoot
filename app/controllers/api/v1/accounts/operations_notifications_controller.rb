# Read + acknowledge endpoint for the operations notification center.
# Notifications are CREATED only via super admin (see
# `SuperAdmin::OperationsNotificationsController`); regular users only LIST
# and ACK them.
class Api::V1::Accounts::OperationsNotificationsController < Api::V1::Accounts::BaseController
  before_action :fetch_notification, only: [:acknowledge]

  # Top of the inbox bell — "Central de Notificação" listing.
  # Returns up to 10 most-recent visible notifications, with `acknowledged_at`
  # populated when the current user has already dismissed them.
  def index
    notifications = OperationsNotification.visible_for(current_user, current_account).limit(10).to_a
    @notifications = decorate_with_acks(notifications)
  end

  # What the modal asks for on login + polling: only those NOT yet acked.
  # A campaign notification is also filtered out when the current user is
  # not a required signer for the campaign in this account, or has already
  # signed — the audience filter says "managers of this account" but a
  # campaign may target only some of them.
  def pending
    notifications = OperationsNotification.pending_for(current_user, current_account)
                                          .order(severity: :desc, created_at: :desc)
                                          .to_a
    @notifications = decorate_with_acks(reject_terms_without_pending_signature(notifications))
  end

  # User clicks "Entendi". Idempotent — repeated calls return the existing ack.
  def acknowledge
    @ack = OperationsNotificationAck.find_or_create_by!(
      operations_notification_id: @notification.id,
      user_id: current_user.id
    ) do |ack|
      ack.account_id = current_account.id
      ack.acknowledged_at = Time.current
      ack.ip = request.remote_ip
      ack.user_agent = request.user_agent
    end
    render json: { success: true, acknowledged_at: @ack.acknowledged_at.to_i }
  end

  private

  def fetch_notification
    @notification = OperationsNotification.visible_for(current_user, current_account).find(params[:id])
  end

  def decorate_with_acks(notifications)
    return [] if notifications.empty?

    ack_lookup = OperationsNotificationAck
                 .where(operations_notification_id: notifications.map(&:id), user_id: current_user.id)
                 .index_by(&:operations_notification_id)
    notifications.map { |n| [n, ack_lookup[n.id], terms_context_for(n)] }
  end

  # Pre-computes the pending acceptance + pinned version for a re-signature
  # campaign so the jbuilder does not need account-scoped lookups.
  def terms_context_for(notification)
    return nil unless notification.subject_type == 'TermsAcceptanceRequest'

    account_user = current_account_user
    return nil if account_user.blank?

    acceptance = notification.subject&.terms_acceptances
                             &.find_by(account_id: current_account.id, account_user_id: account_user.id)
    return nil if acceptance.blank?

    { acceptance: acceptance, version: notification.subject.terms_version }
  end

  def current_account_user
    @current_account_user ||= AccountUser.find_by(user_id: current_user.id, account_id: current_account.id)
  end

  def reject_terms_without_pending_signature(notifications)
    account_user = current_account_user
    notifications.reject do |notification|
      next false unless notification.subject_type == 'TermsAcceptanceRequest'
      next true if account_user.blank?

      acceptance = notification.subject&.terms_acceptances
                               &.find_by(account_id: current_account.id, account_user_id: account_user.id)
      acceptance.blank? || acceptance.status_signed?
    end
  end
end
