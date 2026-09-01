class AddTokenCardWaiverToSalesQuotes < ActiveRecord::Migration[7.1]
  def change
    # A customer who paid the year by PIX often has no card to leave on file.
    # The token usage still has to be charged, by invoice, and this is what says
    # so — and what lets the flow move past the step asking for a card.
    add_column :sales_quotes, :token_card_waived_at, :datetime
  end
end
