# The conversation of the current user with one AI teammate.
class Api::V2::Accounts::VirtualClinic::ThreadsController < Api::V1::Accounts::BaseController
  MESSAGES_SHOWN = 50

  before_action { authorize :virtual_clinic, :ai_team? }
  before_action :set_persona

  def show
    render_thread(current_thread)
  end

  def messages
    unless ::VirtualClinic::QuestionLimit.new(account: Current.account, user: Current.user).take
      return render json: { error: 'daily_limit_reached' }, status: :too_many_requests
    end

    thread = current_thread
    question = thread.messages.create!(role: :user, status: :done, content: params.require(:content))
    answer = thread.messages.create!(role: :assistant, status: :pending)
    ::VirtualClinic::AnswerJob.perform_later(answer.id)
    render json: { messages: [question, answer].map(&:push_event_data) }
  end

  def reset
    render_thread(VirtualClinicThread.create!(account: Current.account, user: Current.user, persona: @persona.key))
  end

  private

  def set_persona
    @persona = ::VirtualClinic::Persona.find!(params[:persona])
  end

  def current_thread
    VirtualClinicThread.current_for(account: Current.account, user: Current.user, persona: @persona.key)
  end

  def render_thread(thread)
    render json: { persona: @persona.as_json, thread_id: thread.id,
                   messages: thread.messages.last(MESSAGES_SHOWN).map(&:push_event_data) }
  end
end
