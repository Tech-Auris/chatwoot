# The global Base Prompt (row 1 of `secretary_prompts`, the one the flows read).
class Api::V1::AurisAdmin::SecretaryPromptsController < Api::V1::AurisAdmin::BaseController
  def show
    @secretary_prompt = SecretaryPrompt.order(:id).first
    head :not_found if @secretary_prompt.nil?
  end
end
