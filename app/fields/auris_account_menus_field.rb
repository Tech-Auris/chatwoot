require 'administrate/field/base'

# Sidebar visibility toggles rendered as a dedicated Administrate field in the
# Super Admin → Accounts edit page. Sibling to AurisAccountSettingsField, but
# kept separate so these flags never leak into the webhook payload — they're
# pure navigation/access controls, not business behavior.
class AurisAccountMenusField < Administrate::Field::Base
  def to_s
    'Auris menus'
  end

  def options
    [
      { key: :inbox_view_menu_enabled,
        label: 'Caixa de Entrada',
        checked: resource.inbox_view_menu_enabled },
      { key: :help_center_menu_enabled,
        label: 'Central de Ajuda',
        checked: resource.help_center_menu_enabled },
      { key: :campaigns_live_chat_menu_enabled,
        label: 'Campanhas / Chat ao vivo',
        checked: resource.campaigns_live_chat_menu_enabled },
      { key: :campaigns_sms_menu_enabled,
        label: 'Campanhas / SMS',
        checked: resource.campaigns_sms_menu_enabled },
      { key: :settings_macros_menu_enabled,
        label: 'Configurações / Macros',
        checked: resource.settings_macros_menu_enabled }
    ]
  end
end
