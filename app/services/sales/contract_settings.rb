# Switches on Super Admin → Commercial → Contrato. Both start on.
module Sales::ContractSettings
  KEYS = { enabled: 'COMMERCIAL_CONTRACT_ENABLED', auto_sign: 'COMMERCIAL_CONTRACT_AUTO_SIGN' }.freeze

  module_function

  # Semiannual and annual plans go through the Contrato step before paying.
  def enabled?
    read(:enabled)
  end

  # Auris's legal representative (the Autentique token's user) signs every
  # contract right after it is created, before it goes to the customer.
  def auto_sign?
    read(:auto_sign)
  end

  def update!(enabled:, auto_sign:)
    { enabled: enabled, auto_sign: auto_sign }.each do |key, value|
      InstallationConfig.find_or_initialize_by(name: KEYS[key]).update!(value: ActiveModel::Type::Boolean.new.cast(value), locked: false)
    end
    GlobalConfig.clear_cache
  end

  def read(key)
    ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load(KEYS[key], 'true').to_s)
  end
end
