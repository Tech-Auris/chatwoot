# What the Clínica virtual page needs to know before drawing the AI team:
# whether this user sees it, and whether (or why not) they can talk to it.
class Api::V2::Accounts::VirtualClinic::ConfigsController < Api::V1::Accounts::BaseController
  def show
    authorize :virtual_clinic, :show?
    policy = VirtualClinicPolicy.new(pundit_user, :virtual_clinic)
    render json: {
      ai_team: {
        visible: policy.ai_team_visible?,
        chat_enabled: policy.ai_chat?,
        chat_missing: policy.ai_team_manager? ? policy.missing_requirement : nil,
        members: ::VirtualClinic::Persona.all(account: Current.account).map(&:as_json),
        manages_team: policy.ai_team_manager?,
        daily_question_limit: ::VirtualClinic::QuestionLimit.for(Current.account),
        can_manage_settings: policy.update_settings?,
        can_edit_layout: policy.update_layout?,
        seasons: seasons
      },
      assets_version: ::VirtualClinic::AssetStore.version
    }
  end

  private

  # The decoration packs in season now, and every seasonal folder/accessory
  # (hidden out of season).
  def seasons
    today = Time.current.in_time_zone(Current.account.reporting_timezone.presence || 'America/Sao_Paulo').to_date
    active = ::VirtualClinic::Season.active(today).map do |season|
      season.slice(:key, :folder, :accessory).merge(until: season[:to] && Date.new(today.year, *season[:to]).strftime('%d/%m'))
    end
    { active: active,
      folders: ::VirtualClinic::Season.folders, accessories: ::VirtualClinic::Season.accessories }
  end
end
