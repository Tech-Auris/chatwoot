class ChangeInboxTimezoneDefaultToSaoPaulo < ActiveRecord::Migration[7.1]
  def change
    change_column_default :inboxes, :timezone, from: 'UTC', to: 'America/Sao_Paulo'
  end
end
