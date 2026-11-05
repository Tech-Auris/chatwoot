# Coexistence onboarding: asks Meta for the WhatsApp Business app's contacts
# and then its chat history. Meta only honors each request once, and only in
# the 24h after onboarding, so each step is recorded on `history_import` and
# a retry skips what already went through.
#
# `requested_at` is also the reference of the import cutoff: messages older
# than Whatsapp::CloudHistoryImportService::MAX_DAYS before it are dropped.
class Channels::Whatsapp::CoexistenceSyncRequestJob < ApplicationJob
  queue_as :high

  retry_on StandardError, wait: :polynomially_longer, attempts: 8

  def perform(channel_id)
    channel = Channel::Whatsapp.find_by(id: channel_id)
    return unless channel&.provider == 'whatsapp_cloud'

    request_once(channel, 'smb_app_state_sync', 'contacts_requested_at')
    request_once(channel, 'history', 'requested_at')
  end

  private

  def request_once(channel, sync_type, state_key)
    return if channel.history_import_state&.dig(state_key).present?

    Whatsapp::FacebookApiClient.new(channel.provider_config['api_key'])
                               .request_smb_app_data(channel.provider_config['phone_number_id'], sync_type)
    channel.with_lock do
      channel.update_history_import_state!(state_key => Time.current.iso8601, 'status' => 'in_progress')
    end
  end
end
