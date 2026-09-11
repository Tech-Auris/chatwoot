# The fork's operator base is Brazilian; a fresh account defaulting to
# English on the Super Admin form meant every account creation had to
# remember to flip the Locale combobox to pt_BR. Move the column default
# to 16 (pt_BR — see `config/initializers/languages.rb`) so the form
# renders with the right locale already selected.
#
# Existing rows are NOT touched — the change only affects subsequent
# inserts. Accounts already set to en (or anything else) stay as they
# are.
class ChangeAccountsLocaleDefaultToPtBr < ActiveRecord::Migration[7.1]
  # LANGUAGES_CONFIG maps the integer enum -> ISO code. 16 is pt_BR.
  # Pinning the literal here keeps the migration parseable in isolation
  # from that config file (which the initializer loads at boot).
  PT_BR_ENUM_INTEGER = 16
  EN_ENUM_INTEGER = 0

  def up
    change_column_default :accounts, :locale, from: EN_ENUM_INTEGER, to: PT_BR_ENUM_INTEGER
  end

  def down
    change_column_default :accounts, :locale, from: PT_BR_ENUM_INTEGER, to: EN_ENUM_INTEGER
  end
end
