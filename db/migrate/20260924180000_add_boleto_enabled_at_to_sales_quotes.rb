# The boleto option is off by default and only shows up on the public
# proposal after the seller explicitly enables it from the Reservations
# grid — same shape as `token_card_waived_at`, a nullable timestamp that
# doubles as both "is it on" and "when did we turn it on".
#
# Backward compatibility: quotes reserved before this ship stay closed to
# boleto until the seller re-enables it. The seller keeps `card` and `pix`
# available as they were.
class AddBoletoEnabledAtToSalesQuotes < ActiveRecord::Migration[7.1]
  def change
    add_column :sales_quotes, :boleto_enabled_at, :datetime
  end
end
