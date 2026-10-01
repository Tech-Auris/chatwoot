# JSON backend of the "Secretária" field on the Super Admin account edit
# page: loads the options and regenerates the signing secret. The version and
# inboxes themselves are saved with the account form (AccountsController#update).
class SuperAdmin::AccountSecretariesController < SuperAdmin::ApplicationController
  before_action :set_account

  def show
    render json: payload
  end

  def regenerate_secret
    secretary = @account.account_secretary || @account.create_account_secretary!
    secretary.reset_secret!
    render json: payload
  end

  private

  def set_account
    @account = Account.find(params[:account_id])
  end

  def regular_inboxes
    @account.inboxes.where.not(channel_type: 'Channel::Simulator')
  end

  def payload
    secretary = @account.reload.account_secretary
    {
      versions: SecretaryVersion.ordered.map { |version| version.slice(:id, :name, :status) },
      inboxes: regular_inboxes.order(:name).map { |inbox| { id: inbox.id, name: inbox.name, enabled: inbox.secretary_enabled } },
      simulator_inbox: @account.inboxes.find_by(channel_type: 'Channel::Simulator')&.slice(:id, :name),
      secretary_version_id: secretary&.secretary_version_id,
      simulator_version_id: secretary&.simulator_version_id,
      secret: secretary&.secret
    }
  end
end
