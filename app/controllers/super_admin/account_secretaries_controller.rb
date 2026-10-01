# JSON backend of the "Secretária" section on the Super Admin account page:
# version, inboxes it answers on, Simulador version and signing secret.
class SuperAdmin::AccountSecretariesController < SuperAdmin::ApplicationController
  before_action :set_account

  def show
    render json: payload
  end

  def update
    secretary = @account.account_secretary || @account.build_account_secretary
    ActiveRecord::Base.transaction do
      secretary.update!(secretary_params)
      update_enabled_inboxes(Array(params[:inbox_ids]).map(&:to_i))
    end
    render json: payload
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
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

  def secretary_params
    params.permit(:secretary_version_id, :simulator_version_id)
  end

  def regular_inboxes
    @account.inboxes.where.not(channel_type: 'Channel::Simulator')
  end

  def update_enabled_inboxes(ids)
    regular_inboxes.where(id: ids).update_all(secretary_enabled: true) # rubocop:disable Rails/SkipsModelValidations
    regular_inboxes.where.not(id: ids).update_all(secretary_enabled: false) # rubocop:disable Rails/SkipsModelValidations
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
