class ApplicationJob < ActiveJob::Base
  # Changes made by a job show up as "job" in the activity log, unless it runs
  # inline inside a request, which already set its own origin.
  around_perform do |_job, block|
    previous_source = Current.audit_source
    Current.audit_source ||= 'job'
    block.call
  ensure
    Current.audit_source = previous_source
  end

  # https://api.rubyonrails.org/v5.2.1/classes/ActiveJob/Exceptions/ClassMethods.html
  discard_on ActiveJob::DeserializationError do |job, error|
    Rails.logger.info("Skipping #{job.class} with #{
      job.instance_variable_get(:@serialized_arguments)
    } because of ActiveJob::DeserializationError (#{error.message})")
  end
end
