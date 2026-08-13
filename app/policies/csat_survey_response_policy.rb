class CsatSurveyResponsePolicy < ApplicationPolicy
  # Aligns with ReportPolicy: managers own operations (inboxes, teams,
  # agents) and need the CSAT report to steer coaching and quality —
  # the frontend already grants them the route, so the API has to match.
  def index?
    admin_or_manager?
  end

  def metrics?
    admin_or_manager?
  end

  def download?
    admin_or_manager?
  end

  private

  def admin_or_manager?
    @account_user.administrator? || @account_user.manager?
  end
end

CsatSurveyResponsePolicy.prepend_mod_with('CsatSurveyResponsePolicy')
