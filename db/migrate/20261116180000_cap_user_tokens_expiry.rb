# Tokens issued before the 7-day lifespan kept a 2-month expiry; cap them at
# 7 days from now so every open session follows the new rule.
class CapUserTokensExpiry < ActiveRecord::Migration[7.1]
  def up
    cap = 7.days.from_now.to_i

    User.where.not(tokens: nil).find_each do |user|
      capped = user.tokens.transform_values { |token| token.merge('expiry' => [token['expiry'].to_i, cap].min) }
      user.update_column(:tokens, capped) unless capped == user.tokens # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def down; end
end
