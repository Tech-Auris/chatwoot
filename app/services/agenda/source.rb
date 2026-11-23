# The clinic's agenda read live from the ERP or calendar it schedules in, for
# the ERP → Agenda screen. Nothing is copied into our database: each source
# asks its ERP for the period on screen, with a short cache so going back and
# forth between days doesn't call the ERP on every click.
#
# A source takes the account's integration (the `account_integrations` row of
# the account's ERP) and answers in the same shape for every ERP:
#
#   professionals          => [{ id:, name: }]
#   appointments(from, to) => [{ id:, starts_at:, ends_at:, patient_name:,
#                                professional_id:, professional_name:,
#                                procedure_name:, status: }]
#
# `from` and `to` are dates (both included), times are ISO 8601 and `status` is
# one of STATUSES. A failure talking to the ERP raises Error with a message the
# screen can show. A source that couldn't fill everything in time (patient
# names looked up one by one, say) answers `complete?` false, and the screen
# asks again to fill the rest; each source caches what it reads from its ERP.
class Agenda::Source
  class Error < StandardError; end

  STATUSES = %w[scheduled confirmed rescheduled waiting in_progress attended no_show canceled].freeze
  MAX_DAYS = 7
  # The source class of each ERP that has one, by `erp_sources` id.
  SOURCES = { 2 => 'Agenda::Sources::Erp2' }.freeze

  attr_reader :integration

  def self.for(account)
    source = SOURCES[account.erp_source_id]
    integration = source && account.account_integrations.find_by(erp_source_id: account.erp_source_id)
    source.constantize.new(integration) if integration
  end

  def self.available?(account)
    SOURCES.key?(account.erp_source_id) && account.account_integrations.exists?(erp_source_id: account.erp_source_id)
  end

  def initialize(integration)
    @integration = integration
  end

  def agenda(from, to)
    appointments = appointments(from, to)
    { professionals: professionals, appointments: appointments, complete: complete? }
  end

  def professionals
    raise NotImplementedError
  end

  def appointments(_from, _to)
    raise NotImplementedError
  end

  def complete?
    true
  end

  private

  # Saving the integration (a new token, say) starts a fresh cache.
  def cached(*key, expires_in:, &)
    Rails.cache.fetch(['agenda', integration.id, integration.updated_at.to_i, *key], expires_in: expires_in, &)
  end
end
