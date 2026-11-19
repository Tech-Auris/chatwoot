# Daily cap of questions per user to the AI team. The clinic pays the OpenAI
# key, so its administrator sets the cap (Clínica virtual settings): 60 by
# default, blank for no limit.
class VirtualClinic::QuestionLimit
  SETTING = 'virtual_clinic_daily_question_limit'.freeze
  DEFAULT = 60

  def self.for(account)
    account.settings.key?(SETTING) ? account.settings[SETTING] : DEFAULT
  end

  def initialize(account:, user:)
    @limit = self.class.for(account)
    @key = "virtual_clinic:questions:#{account.id}:#{user.id}:#{Date.current}"
  end

  # Counts the question and says whether it still fits today's cap.
  def take
    return true if @limit.nil?

    count = Redis::Alfred.incr(@key)
    Redis::Alfred.expire(@key, 1.day.to_i) if count == 1
    count <= @limit
  end
end
