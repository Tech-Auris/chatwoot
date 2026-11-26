require 'rails_helper'

describe Whatsapp::ApiError do
  describe '.from_response' do
    it "keeps Meta's code and subcode next to the caller's message" do
      response = instance_double(HTTParty::Response, code: 400,
                                                     parsed_response: { 'error' => { 'code' => 100, 'error_subcode' => 33 } })

      error = described_class.from_response(response, message: 'App subscription to WABA failed: {...}')

      expect(error.message).to eq('App subscription to WABA failed: {...}')
      expect([error.http_status, error.code, error.subcode]).to eq([400, 100, 33])
    end

    it 'leaves the code nil when the body is not the shape Meta documents' do
      response = instance_double(HTTParty::Response, code: 502, parsed_response: '<html>502 Bad Gateway</html>')

      expect(described_class.from_response(response, message: 'failed').code).to be_nil
    end

    it 'leaves the code nil when the error is a plain string' do
      response = instance_double(HTTParty::Response, code: 400, parsed_response: { 'error' => 'Invalid code' })

      expect(described_class.from_response(response, message: 'failed').code).to be_nil
    end
  end

  describe '#credentials_refused?' do
    def error(code, subcode = nil)
      described_class.new(message: 'x', http_status: 400, code: code, subcode: subcode)
    end

    it 'is true for a revoked token (190), also when the code came as a string' do
      expect(error(190)).to be_credentials_refused
      expect(error('190')).to be_credentials_refused
    end

    it 'is true when the token no longer sees the WABA (100/33)' do
      expect(error(100, 33)).to be_credentials_refused
    end

    it 'is false for any other refusal or for no code at all' do
      expect([error(100), error(200), error(4), error(nil)].map(&:credentials_refused?)).to all(be(false))
    end
  end
end
