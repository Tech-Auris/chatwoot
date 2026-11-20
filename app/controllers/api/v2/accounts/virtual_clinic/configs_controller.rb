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
        can_edit_layout: policy.update_layout?
      }
    }
  end
end
