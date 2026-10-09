# Recall API for the n8n FUP workflow: it records each follow-up it starts,
# then reports whether the message went out and whether the patient came
# back. `PATCH .../follow_ups/latest` updates the conversation's most recent
# FUP, for the "a previous FUP got a reply" case where n8n no longer has its id.
class Api::V1::Accounts::Conversations::FollowUpsController < Api::V1::Accounts::Conversations::BaseController
  before_action :follow_up, only: [:update]

  def index
    authorize FollowUp
    @follow_ups = @conversation.follow_ups.order(:created_at)
    @follow_ups = @follow_ups.where(run_id: params[:run_id]) if params[:run_id].present?
  end

  # A new FUP means the ones still waiting got no answer.
  def create
    authorize FollowUp
    ActiveRecord::Base.transaction do
      @conversation.follow_ups.outcome_waiting.update_all(outcome: :no_response, outcome_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      @follow_up = @conversation.follow_ups.create!(
        create_params.merge(account: Current.account, inbox: @conversation.inbox)
      )
    end
  end

  def update
    @follow_up.update!(update_params)
  end

  private

  def follow_up
    authorize FollowUp
    scope = @conversation.follow_ups
    @follow_up = params[:id] == 'latest' ? scope.order(:created_at).last! : scope.find(params[:id])
  end

  def create_params
    params.permit(:run_id, :step, :delay_minutes)
  end

  def update_params
    params.permit(:delivery_status, :outcome, :error_message, :message_id)
  end
end
