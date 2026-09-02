# Dev-only stub for the ClickUp prospect list. When
# CLICKUP_PROSPECT_STUB=1 is set, Sales::ClickupProspectSearchService
# reads from a fixed fixture instead of walking the pipeline through
# graph.clickup.com — useful to exercise the "Montar plano" search and
# the reservation-sync flow without a valid ClickUp token, without
# CLICKUP_PIPELINE_LIST_ID configured, and without touching real deals.
#
# Never active in production. Rows here span open statuses (search
# picks them up) and closed ones (`ganho`/`perdido`, which `find` still
# resolves for the Reservations sync).
return unless Rails.env.development? && ENV['CLICKUP_PROSPECT_STUB'] == '1'

require Rails.root.join('lib/dev/stub_prospects')

# `to_prepare` runs at boot AND on every code reload in dev, so the
# monkey-patch survives when Rails swaps a class after an edit. Using
# `after_initialize` here would apply the override once at boot and
# lose it as soon as the ClickUp client (or anything in its autoload
# tree) got reloaded, and the "não configurado" banner would come
# back mid-session for no visible reason.
Rails.application.config.to_prepare do
  Sales::ClickupProspectSearchService.class_eval do
    define_method(:prospects) { Dev::StubProspects::PROSPECTS }
    # `list_id` would still raise NotConfigured without a real GlobalConfig
    # entry — override it so the stub works on a fresh dev DB.
    define_method(:list_id) { 'STUB_LIST' }
  end

  # The Commercial pages read `Integrations::Clickup::Client.new.configured?`
  # to decide whether to hide their "não configurado" banner and enable the
  # sync calls; the stub speaks the same protocol so the UI is not held up
  # by a missing token in dev.
  Integrations::Clickup::Client.class_eval do
    define_method(:configured?) { true }
  end
end
