# Classified send errors for the WhatsApp providers (today: Baileys).
#
# `code` is what callers match on (e.g. which errors do not mean the connection is down) and
# `retryable?` answers whether running the same send again could produce a different answer.
# The message is the human-readable reason stored as the message's external_error.
module Whatsapp::Providers::Errors
  class Error < StandardError
    CODE = 'provider_error'.freeze

    def code
      self.class::CODE
    end

    def retryable?
      false
    end
  end

  # The provider could not be reached or answered with something we cannot act on. The same
  # send can work once it is back.
  class ProviderUnavailable < Error
    CODE = 'provider_unavailable'.freeze

    def retryable?
      true
    end
  end

  # The send reached its deadline. It may still reach WhatsApp; the idempotency key makes the
  # retry answer with the outcome instead of sending twice.
  class SendTimeout < ProviderUnavailable # rubocop:disable Style/OneClassPerFile
    CODE = 'timeout'.freeze
  end

  # The connection is up and receiving, but the provider's send-stall breaker refused the
  # send without touching the socket. The provider recreates the socket on its own.
  class SendStalled < ProviderUnavailable # rubocop:disable Style/OneClassPerFile
    CODE = 'send_stalled'.freeze
  end

  # A previous attempt timed out and may or may not have reached WhatsApp. Only a person
  # checking the conversation can tell, so it is never retried.
  class SendOutcomeUnknown < Error
    CODE = 'send_outcome_unknown'.freeze
  end

  # Another worker holds the provider's idempotency lock for this message: it is still on
  # its way out. SendReplyJob gives it its own backoff.
  class MessageAlreadyProcessing < Error
    CODE = 'message_already_processing'.freeze
  end

  class MediaTooLarge < Error
    CODE = 'media_too_large'.freeze
  end

  class InvalidPayload < Error
    CODE = 'invalid_payload'.freeze
  end
end
