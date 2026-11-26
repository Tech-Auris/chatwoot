# Meta can accept the connection and then stay quiet, and Net::HTTP waits 60s by default and retries
# an idempotent request once (a GET would hold a Puma thread for 120s). Every Graph call made by the
# setup and health services gets a 10s ceiling with no retry.
module Whatsapp::GraphRequestOptions
  GRAPH_REQUEST_OPTIONS = { timeout: 10, max_retries: 0 }.freeze
end
