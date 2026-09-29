# Checks, when an ad account is added to the grid, that the integration's
# token can read it — and fetches its name and currency for display. Failing
# here tells the operator right away that the token lacks `ads_read` on that
# account, instead of an empty report the next day.
class Marketing::MetaAdAccountLookup
  META_API_VERSION = Marketing::MetaSpendFetcher::META_API_VERSION

  Result = Struct.new(:ok, :name, :currency, :error, keyword_init: true)

  pattr_initialize [:integration!, :external_id!]

  def perform
    response = HTTParty.get(
      "https://graph.facebook.com/#{META_API_VERSION}/act_#{external_id}",
      query: { fields: 'name,currency', access_token: integration.ads_read_access_token },
      timeout: 10
    )
    body = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    return Result.new(ok: true, name: body['name'], currency: body['currency']) if response.success?

    Result.new(ok: false, error: body.dig('error', 'message') || "HTTP #{response.code}")
  rescue StandardError => e
    Result.new(ok: false, error: e.message)
  end
end
