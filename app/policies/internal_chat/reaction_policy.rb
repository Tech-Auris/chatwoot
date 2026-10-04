class InternalChat::ReactionPolicy < ApplicationPolicy
  def create?
    channel_accessible?
  end

  def destroy?
    return false unless channel_accessible?
    return true if administrator?

    record.user_id == @user.id
  end

  private

  def channel
    record.respond_to?(:message) && record.message.present? ? record.message.channel : nil
  end

  def administrator?
    @account_user&.administrator?
  end

  # DMs are only for the two people in them, account administrators included.
  def channel_accessible?
    ch = channel
    return false if ch.blank?
    return ch.channel_members.exists?(user_id: @user.id) if ch.channel_type_dm?
    return true if administrator?

    return @account_user.present? if ch.channel_type_public_channel?

    ch.channel_members.exists?(user_id: @user.id)
  end
end
