require 'administrate/field/text'

# Text edited in a wide textarea sized to its content, for long prompt-like
# texts such as the secretary special scenarios.
class LongTextField < Administrate::Field::Text
  MIN_ROWS = 6
  MAX_ROWS = 40
  CHARS_PER_ROW = 110

  def rows
    (data.to_s.lines.sum { |line| (line.length / CHARS_PER_ROW) + 1 } + 1).clamp(MIN_ROWS, MAX_ROWS)
  end
end
