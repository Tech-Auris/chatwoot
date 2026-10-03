# Thin wrapper around the Autentique GraphQL API, where the semiannual and
# annual contracts of the hiring area are signed. Every call is a POST to one
# endpoint; the document upload follows the GraphQL multipart spec.
#
# The token belongs to an Autentique user, and `sign_document` signs as that
# user — which is how Auris's legal representative signs every contract
# automatically before it goes to the customer.
class Integrations::Autentique::Client
  ENDPOINT = 'https://api.autentique.com.br/v2/graphql'.freeze
  DEFAULT_TIMEOUT = 20

  class Error < StandardError; end
  class Unauthorized < Error; end
  class ProviderUnavailable < Error; end

  DOCUMENT_FIELDS = <<~GRAPHQL.freeze
    id
    name
    sandbox
    deadline_at
    created_at
    signatures {
      public_id
      name
      email
      action { name }
      link { short_link }
      viewed { created_at }
      signed { created_at }
      rejected { created_at }
    }
    files { original signed }
  GRAPHQL

  def initialize(api_token: nil)
    @api_token = api_token.presence || GlobalConfig.get('AUTENTIQUE_API_TOKEN')['AUTENTIQUE_API_TOKEN']
  end

  def configured?
    @api_token.present?
  end

  # The Autentique user the token belongs to — the one `sign_document` signs as.
  def me
    query('query { me { id name email } }').fetch('me')
  end

  # Creates the document and invites the signers. With `sortable`, each signer
  # is only invited after the previous one signed.
  def create_document(name:, io:, filename:, signers:, deadline_at: nil, sandbox: false, sortable: true) # rubocop:disable Metrics/ParameterLists
    operations = {
      query: <<~GRAPHQL,
        mutation CreateDocument($document: DocumentInput!, $signers: [SignerInput!]!, $file: Upload!) {
          createDocument(document: $document, signers: $signers, file: $file, sandbox: #{sandbox ? 'true' : 'false'}) { #{DOCUMENT_FIELDS} }
        }
      GRAPHQL
      variables: {
        document: { name: name, sortable: sortable, deadline_at: deadline_at&.utc&.iso8601(3) }.compact,
        signers: signers,
        file: nil
      }
    }
    upload(operations, io: io, filename: filename).fetch('createDocument')
  end

  def document(id)
    query("query($id: UUID!) { document(id: $id) { #{DOCUMENT_FIELDS} } }", id: id).fetch('document')
  end

  # Signs as the token's user, who must be one of the document's signers.
  def sign_document(id)
    query('mutation($id: UUID!) { signDocument(id: $id) }', id: id).fetch('signDocument')
  end

  def update_deadline(id, deadline_at)
    query('mutation($id: UUID!, $document: UpdateDocumentInput!) { updateDocument(id: $id, document: $document) { id deadline_at } }',
          id: id, document: { deadline_at: deadline_at.utc.iso8601(3) }).fetch('updateDocument')
  end

  # Autentique only moves a document someone already signed to the trash
  # without blocking it; an unsigned one is taken down.
  def delete_document(id)
    query('mutation($id: UUID!) { deleteDocument(id: $id) }', id: id).fetch('deleteDocument')
  end

  private

  def query(graphql, variables = {})
    response = HTTParty.post(ENDPOINT, headers: headers.merge('Content-Type' => 'application/json'),
                                       body: { query: graphql, variables: variables }.to_json, timeout: DEFAULT_TIMEOUT)
    parse(response)
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise ProviderUnavailable, e.message
  end

  # HTTParty names the multipart part after the file's path, so the bytes are
  # copied under the real filename first (same as the ClickUp attachment).
  def upload(operations, io:, filename:)
    Dir.mktmpdir('autentique-upload') do |dir|
      path = File.join(dir, File.basename(filename.to_s))
      File.open(path, 'wb') { |f| IO.copy_stream(io, f) }
      File.open(path, 'rb') do |file|
        response = HTTParty.post(ENDPOINT, headers: headers, multipart: true, timeout: DEFAULT_TIMEOUT,
                                           body: { operations: operations.to_json, map: { file: ['variables.file'] }.to_json, file: file })
        return parse(response)
      end
    end
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise ProviderUnavailable, e.message
  end

  def headers
    { 'Authorization' => "Bearer #{@api_token}" }
  end

  def parse(response)
    raise Unauthorized, 'Autentique recusou o token' if [401, 403].include?(response.code)
    raise ProviderUnavailable, "Autentique #{response.code}: #{response.body.to_s.truncate(300)}" unless response.success?

    body = response.parsed_response
    raise_graphql_errors(body['errors']) if body['errors'].present?

    body.fetch('data')
  end

  # GraphQL answers 200 even when it refuses the call; the reason is in `errors`.
  def raise_graphql_errors(errors)
    message = Array(errors).filter_map { |error| error['message'] }.join(', ')
    raise Unauthorized, message if message.match?(/unauthenticated|unauthorized/i)

    raise Error, message
  end
end
