require 'administrate/field/base'

# Sidebar visibility toggles rendered as a dedicated Administrate field in the
# Super Admin → Accounts edit page. Sibling to AurisAccountSettingsField, but
# kept separate so these flags never leak into the webhook payload — they're
# pure navigation/access controls, not business behavior.
class AurisAccountMenusField < Administrate::Field::Base
  def to_s
    'Auris menus'
  end

  MENUS = {
    inbox_view_menu_enabled: 'Caixa de Entrada',
    help_center_menu_enabled: 'Central de Ajuda',
    campaigns_live_chat_menu_enabled: 'Campanhas / Chat ao vivo',
    campaigns_sms_menu_enabled: 'Campanhas / SMS',
    settings_macros_menu_enabled: 'Configurações / Macros',
    virtual_clinic_enabled: 'Clínica virtual'
  }.freeze

  def options
    MENUS.map { |key, label| { key: key, label: label, checked: resource.public_send(key) } }
  end
end
