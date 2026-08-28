require 'rails_helper'

RSpec.describe TermsAcceptance do
  let(:version) { create(:terms_version, content: 'Termos versão 1') }

  describe TermsVersion do
    # Fetching the same unchanged page twice must not pile up copies, or the
    # audit trail fills with duplicates of the same contract.
    it 'reuses the version when the content has not changed' do
      first = described_class.for_content('https://exemplo.com/termos', 'Mesmo texto')
      second = described_class.for_content('https://exemplo.com/termos', 'Mesmo texto')

      expect(second.id).to eq(first.id)
    end

    it 'creates a new version when the text changes' do
      first = described_class.for_content('https://exemplo.com/termos', 'Texto antigo')
      second = described_class.for_content('https://exemplo.com/termos', 'Texto novo')

      expect(second.id).not_to eq(first.id)
      expect(second.content_hash).not_to eq(first.content_hash)
    end
  end

  describe '#sign!' do
    it 'records who signed, when, and from where' do
      acceptance = create(:terms_acceptance, terms_version: version)

      acceptance.sign!(
        signer: { name: 'Maria Souza', email: 'maria@exemplo.com', document: '123.456.789-00' },
        ip_address: '201.10.0.1',
        user_agent: 'Mozilla/5.0'
      )

      expect(acceptance.reload).to have_attributes(
        status: 'signed', signer_name: 'Maria Souza', ip_address: '201.10.0.1', user_agent: 'Mozilla/5.0'
      )
      expect(acceptance.signed_at).to be_present
    end

    # The signature points at a frozen copy: what was agreed has to stay
    # readable even after the public page changes.
    it 'keeps pointing at the text that was signed' do
      acceptance = create(:terms_acceptance, terms_version: version)
      acceptance.sign!(signer: { name: 'Maria', email: 'maria@exemplo.com' }, ip_address: '1.1.1.1', user_agent: 'x')

      TermsVersion.for_content(version.source_url, 'Termos versão 2 — outra redação')

      expect(acceptance.reload.terms_version.content).to eq('Termos versão 1')
    end
  end

  describe 'signature requests' do
    # A re-signature asked of an existing account has no proposal to ride on,
    # so it carries a link of its own.
    it 'issues a token when there is no sale behind it' do
      acceptance = create(:terms_acceptance, terms_version: version, account: create(:account))

      expect(acceptance.request_token).to be_present
    end

    it 'does not issue one when the signature belongs to a proposal' do
      acceptance = create(:terms_acceptance, terms_version: version, sales_quote: create(:sales_quote))

      expect(acceptance.request_token).to be_nil
    end
  end
end
