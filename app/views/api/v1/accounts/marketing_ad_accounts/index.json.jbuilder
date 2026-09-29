json.payload do
  json.array! @ad_accounts, partial: 'ad_account', as: :ad_account
end
