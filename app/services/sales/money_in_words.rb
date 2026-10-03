# Writes a BRL amount out in Portuguese, the way a contract does:
# 184920 → "mil oitocentos e quarenta e nove reais e vinte centavos".
module Sales::MoneyInWords
  UNITS = %w[zero um dois três quatro cinco seis sete oito nove dez onze doze treze quatorze quinze dezesseis dezessete dezoito dezenove].freeze
  TENS = %w[_ _ vinte trinta quarenta cinquenta sessenta setenta oitenta noventa].freeze
  HUNDREDS = %w[_ cento duzentos trezentos quatrocentos quinhentos seiscentos setecentos oitocentos novecentos].freeze
  SCALES = [%w[mil mil], %w[milhão milhões], %w[bilhão bilhões]].freeze

  module_function

  def call(cents)
    reais, centavos = cents.to_i.divmod(100)
    parts = []
    parts << "#{number(reais)} #{currency_word(reais)}" if reais.positive?
    parts << "#{number(centavos)} #{centavos == 1 ? 'centavo' : 'centavos'}" if centavos.positive?
    parts.empty? ? 'zero reais' : parts.join(' e ')
  end

  # Round millions take "de": "um milhão de reais".
  def currency_word(reais)
    return 'real' if reais == 1

    reais >= 1_000_000 && (reais % 1_000_000).zero? ? 'de reais' : 'reais'
  end

  # Whole number in words, e.g. 12 → "doze".
  def number(value)
    return UNITS[0] if value.zero?

    groups = value.digits(1000)
    words = groups.each_with_index.reverse_each.filter_map { |group, index| group_words(group, index) }
    join_groups(words, groups)
  end

  def group_words(group, index)
    return if group.zero?
    return 'mil' if index == 1 && group == 1

    words = hundreds(group)
    return words if index.zero?

    scale = SCALES[index - 1]
    "#{words} #{group == 1 ? scale.first : scale.last}"
  end

  # "e" goes before the last group when it is under 100 or a round hundred
  # ("mil e duzentos", "mil e cinquenta"), a comma-less space otherwise.
  def join_groups(words, groups)
    return words.first if words.size == 1

    last = groups.find(&:positive?)
    connector = last < 100 || (last % 100).zero? ? ' e ' : ' '
    "#{words[0..-2].join(' ')}#{connector}#{words.last}"
  end

  def hundreds(value)
    return 'cem' if value == 100

    hundred, rest = value.divmod(100)
    parts = []
    parts << HUNDREDS[hundred] if hundred.positive?
    parts << below_hundred(rest) if rest.positive?
    parts.join(' e ')
  end

  def below_hundred(value)
    return UNITS[value] if value < 20

    ten, unit = value.divmod(10)
    unit.zero? ? TENS[ten] : "#{TENS[ten]} e #{UNITS[unit]}"
  end
end
