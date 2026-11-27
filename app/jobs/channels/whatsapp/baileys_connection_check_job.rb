class Channels::Whatsapp::BaileysConnectionCheckJob < ApplicationJob
  queue_as :low

  def perform(whatsapp_channel)
    return unless whatsapp_channel.reconnection_enabled?

    whatsapp_channel.setup_channel_provider
    check_send_health(whatsapp_channel)
    refresh_reachout_time_lock(whatsapp_channel)
    refresh_new_chat_cap(whatsapp_channel)
  end

  private

  # setup_channel_provider above does not prove the connection can send. This reports a stall
  # rather than acting on it: the provider recovers on its own (and warns via the
  # send_stall_detected webhook). It does clear a stored stall once sends are confirmed `ok`, so
  # the warning cannot outlive a recovery that came without a new `open` event.
  def check_send_health(whatsapp_channel)
    health = whatsapp_channel.provider_service.fetch_send_health
    return if health.nil?

    clear_send_stall(whatsapp_channel) if health[:send_state] == 'ok'
    return unless health[:send_state] == 'stalled'

    Rails.logger.error(
      "[WHATSAPP][BAILEYS] send stall on ##{whatsapp_channel.id}: " \
      "consecutive_timeouts=#{health[:consecutive_send_timeouts]} " \
      "last_send_completed_ago_ms=#{health[:last_send_completed_ago_ms] || 'never'} " \
      "last_outgoing_ack_ago_ms=#{health[:last_outgoing_ack_ago_ms] || 'never'}"
    )
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP][BAILEYS] send health check failed for ##{whatsapp_channel.id}: #{e.message}")
  end

  def clear_send_stall(whatsapp_channel)
    whatsapp_channel.with_lock do
      next if whatsapp_channel.provider_connection['send_stall'].blank?

      whatsapp_channel.update_provider_connection!(whatsapp_channel.provider_connection.except('send_stall', 'error'))
    end
  end

  # Best-effort: a failed time-lock fetch must not abort the connection check (which also
  # re-arms the session). nil means "unknown" (404/error) — skip so we never clear a banner
  # that a webhook push legitimately set; the banner then falls back to push-driven state.
  def refresh_reachout_time_lock(whatsapp_channel)
    lock = whatsapp_channel.provider_service.fetch_reachout_timelock
    whatsapp_channel.update_reachout_time_lock!(lock) unless lock.nil?
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP][BAILEYS] reachout timelock refresh failed for ##{whatsapp_channel.id}: #{e.message}")
  end

  # Same best-effort contract as refresh_reachout_time_lock: nil (404/error) leaves the last known
  # cap untouched so a transient blip doesn't clear a legitimately-set banner.
  def refresh_new_chat_cap(whatsapp_channel)
    cap = whatsapp_channel.provider_service.fetch_new_chat_cap
    whatsapp_channel.update_new_chat_cap!(cap) unless cap.nil?
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP][BAILEYS] new-chat cap refresh failed for ##{whatsapp_channel.id}: #{e.message}")
  end
end
