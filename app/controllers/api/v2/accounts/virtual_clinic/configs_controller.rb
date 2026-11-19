# What the Clínica virtual page needs to know before drawing the AI team:
# whether this user may see it, and what is still missing to turn it on.
class Api::V2::Accounts::VirtualClinic::ConfigsController < Api::V1::Accounts::BaseController
  def show
    authorize :virtual_clinic, :show?
    policy = VirtualClinicPolicy.new(pundit_user, :virtual_clinic)
    render json: {
      ai_team: {
        visible: policy.ai_team_visible?,
        enabled: policy.ai_team?,
        missing: policy.ai_team_visible? ? policy.missing_requirement : nil,
        members: policy.ai_team_visible? ? ::VirtualClinic::Persona.all.map(&:as_json) : [],
        daily_question_limit: ::VirtualClinic::QuestionLimit.for(Current.account)
      }
    }
  end
end
