class InternalChat::MessagePolicy < ApplicationPolicy
  def index?
    channel_accessible?
  end

  def create?
    channel_accessible?
  end

  def update?
    channel_accessible? && (administrator? || sender?)
  end

  def destroy?
    channel_accessible? && (administrator? || sender?)
  end

  def pin?
    channel_accessible? && (administrator? || channel_admin?)
  end

  def unpin?
    channel_accessible? && (administrator? || channel_admin?)
  end

  def thread?
    channel_accessible?
  end

  private

  def channel
    record.respond_to?(:channel) ? record.channel : record
  end

  def administrator?
    @account_user&.administrator?
  end

  def sender?
    record.sender_id == @user.id
  end

  # DMs are only for the two people in them, account administrators included.
  def channel_accessible?
    return channel.channel_members.exists?(user_id: @user.id) if channel.channel_type_dm?
    return true if administrator?
    return @account_user.present? if channel.channel_type_public_channel?

    channel.channel_members.exists?(user_id: @user.id)
  end

  def channel_admin?
    channel.channel_members.exists?(user_id: @user.id, role: :admin)
  end
end
