class BackfillDetailsConfirmedSalesQuotes < ActiveRecord::Migration[7.1]
  # `details_confirmed` (status = 7) is a new step between `reserved` and
  # `signed`. Any quote still on `draft` (0) or `reserved` (1) whose
  # prospect has already filled every required field belongs on the new
  # step — otherwise the Situação column would keep reading the old label
  # forever, since re-saving the details is what advances the row now.
  #
  # Downstream states (signed / paid / converted) already imply the
  # details are in, and expired / cancelled are terminal; none of them
  # should be moved.
  def up
    execute <<~SQL.squish
      UPDATE sales_quotes
         SET status = 7
       WHERE status IN (0, 1)
         AND prospect_name IS NOT NULL      AND prospect_name      <> ''
         AND company_name IS NOT NULL       AND company_name       <> ''
         AND prospect_email IS NOT NULL     AND prospect_email     <> ''
         AND prospect_phone IS NOT NULL     AND prospect_phone     <> ''
         AND prospect_document IS NOT NULL  AND prospect_document  <> '';
    SQL
  end

  def down
    # Falls back to `reserved`, which is the closest upstream state that
    # keeps the deal on the reservations screen; `draft` would drop it out
    # of the working queue and lose more information than we can safely
    # rebuild from the row alone.
    execute 'UPDATE sales_quotes SET status = 1 WHERE status = 7'
  end
end
