# Validates a Brazilian CPF or CNPJ against its official check-digit
# algorithm.
#
# Both algorithms share a rejection rule that catches the trivial cases the
# form used to accept: a document whose digits are all the same (e.g.
# "00000000000" for CPF) satisfies the arithmetic by chance and still is not
# a real document — Receita Federal treats those as invalid too.
module BrDocumentChecksum
  module_function

  def valid_cpf?(value)
    digits = digits_only(value)
    return false unless digits.length == 11
    return false if digits.chars.uniq.length == 1

    d1 = calc_check_digit(digits[0, 9].chars.map(&:to_i), 10)
    d2 = calc_check_digit(digits[0, 10].chars.map(&:to_i), 11)

    digits[9].to_i == d1 && digits[10].to_i == d2
  end

  def valid_cnpj?(value)
    digits = digits_only(value)
    return false unless digits.length == 14
    return false if digits.chars.uniq.length == 1

    weights_first = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
    weights_second = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]

    d1 = weighted_check_digit(digits[0, 12].chars.map(&:to_i), weights_first)
    d2 = weighted_check_digit(digits[0, 13].chars.map(&:to_i), weights_second)

    digits[12].to_i == d1 && digits[13].to_i == d2
  end

  # A CPF check digit is the weighted sum modulo 11 — but with the twist
  # that a remainder below 2 collapses to 0 rather than 11 - remainder,
  # because Receita never issues a "10" or "11" as a check digit.
  def calc_check_digit(digits, starting_weight)
    sum = digits.each_with_index.sum { |digit, i| digit * (starting_weight - i) }
    remainder = sum % 11
    remainder < 2 ? 0 : 11 - remainder
  end
  private_class_method :calc_check_digit

  def weighted_check_digit(digits, weights)
    sum = digits.each_with_index.sum { |digit, i| digit * weights[i] }
    remainder = sum % 11
    remainder < 2 ? 0 : 11 - remainder
  end
  private_class_method :weighted_check_digit

  def digits_only(value)
    value.to_s.gsub(/\D/, '')
  end
  private_class_method :digits_only
end
