class Api::BaseController < ApplicationController
  include AccessTokenAuthHelper
  respond_to :json
  before_action :authenticate_access_token!, if: :authenticate_by_access_token?
  before_action :validate_bot_access_token!, if: :authenticate_by_access_token?
  before_action :authenticate_user!, unless: :authenticate_by_access_token?
  before_action :set_audit_context

  private

  # Read by ActivityLog; Current.reset clears it after the request.
  def set_audit_context
    Current.audit_source = authenticate_by_access_token? ? 'api' : 'dashboard'
    Current.audit_ip = request.remote_ip
    Current.audit_request_id = request.request_id
  end

  def authenticate_by_access_token?
    request.headers[:api_access_token].present? || request.headers[:HTTP_API_ACCESS_TOKEN].present?
  end

  def check_authorization(model = nil)
    model ||= controller_name.classify.constantize

    authorize(model)
  end

  def check_admin_authorization?
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end

  def check_admin_or_manager_authorization?
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator? || Current.account_user.manager?
  end
end
