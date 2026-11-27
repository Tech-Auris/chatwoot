# CSV writer for every export: defuses cells that a spreadsheet would run as a formula
# (leading `=`, `+`, `-`, `@`, ...) by prefixing them with `'`, as CSVSafe does.
#
# A phone number in E.164 (`+5511999999999`) is the one exception: it is the key column of
# most of our exports, it is a plain number and not a formula, and a `'` in front of it would
# break pasting the list into another tool or re-importing it.
class SafeCsv < CSVSafe
  PHONE_NUMBER = /\A\+\d+\z/

  private

  def sanitize_field(field)
    field.is_a?(String) && field.match?(PHONE_NUMBER) ? field : super
  end
end
