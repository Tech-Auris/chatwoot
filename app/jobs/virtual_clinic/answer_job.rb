class VirtualClinic::AnswerJob < ApplicationJob
  queue_as :default

  def perform(answer_id)
    VirtualClinic::AnswerService.new(VirtualClinicMessage.find(answer_id)).perform
  end
end
