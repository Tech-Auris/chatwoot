# The ERPs clinics schedule in, with the same ids as the Supabase
# `integration_type` table. Read by n8n and the dashboard.
class Api::V1::ErpSourcesController < Api::BaseController
  def index
    @erp_sources = ErpSource.active.ordered
  end
end
