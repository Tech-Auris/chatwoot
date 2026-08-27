class Account::ContactsExportJob < ApplicationJob
  queue_as :low

  def perform(account_id, user_id, column_names, params)
    @account = Account.find(account_id)
    @account_user = @account.users.find(user_id)

    # The CSV itself is built by the service the direct download also uses, so
    # both paths always produce the same file.
    service = Contacts::ExportService.new(account: @account, user: @account_user, column_names: column_names, params: params)
    attach_export_file(service.perform, service.filename)
    send_mail
  end

  private

  def attach_export_file(csv_data, filename)
    return if csv_data.blank?

    @account.contacts_export.attach(io: StringIO.new(csv_data), filename: filename, content_type: 'text/csv')
  end

  def send_mail
    file_url = account_contact_export_url
    mailer = AdministratorNotifications::AccountNotificationMailer.with(account: @account)
    mailer.contact_export_complete(file_url, @account_user.email)&.deliver_later
  end

  def account_contact_export_url
    Rails.application.routes.url_helpers.rails_blob_url(@account.contacts_export)
  end
end
