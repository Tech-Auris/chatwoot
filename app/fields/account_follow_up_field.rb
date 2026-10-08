require 'administrate/field/base'

# "Follow-up" block of the Super Admin account form: the FUP waiting times and
# what happens once they all go unanswered. Saved by
# AccountsController#merge_follow_up into `settings.follow_up`.
class AccountFollowUpField < Administrate::Field::Base
  def to_s
    steps.map { |minutes| "#{minutes} min" }.join(' → ')
  end

  def steps
    Array(data&.dig('steps'))
  end

  # One input per possible FUP, blank ones are dropped on save. Grows past
  # the limit when an invalid submit re-renders the form.
  def step_inputs
    Array.new([Account::MAX_FOLLOW_UP_STEPS, steps.size].max) { |index| steps[index] }
  end

  def end_flow
    data&.dig('end_flow') || {}
  end
end
