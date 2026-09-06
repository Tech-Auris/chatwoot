class BackfillTermsSignatureKindAndDocumentDate < ActiveRecord::Migration[7.1]
  # The existing rows are all sales-checkout signatures; naming them so lets the
  # super_admin report answer "signature vs update" from a single index scan.
  # The document_date reflects the "Última atualização" the marketing page
  # carried on the day the campaign feature shipped.
  LEGACY_DOCUMENT_DATE = Date.new(2026, 9, 3).freeze

  def up
    execute('UPDATE terms_acceptances SET kind = 0 WHERE kind IS NULL')
    execute("UPDATE terms_versions SET document_date = '#{LEGACY_DOCUMENT_DATE.iso8601}' WHERE document_date IS NULL")

    change_column_null :terms_acceptances, :kind, false
    change_column_default :terms_acceptances, :kind, 0
  end

  def down
    change_column_null :terms_acceptances, :kind, true
    change_column_default :terms_acceptances, :kind, nil
    # Data left as-is on rollback — the values are correct even without the enum.
  end
end
