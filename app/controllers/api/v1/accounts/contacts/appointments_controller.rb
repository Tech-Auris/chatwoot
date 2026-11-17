# Every appointment of the contact, newest first, for the "Agendamentos"
# section of the conversation sidebar. Same reach as the contact's
# conversation list: an agent only sees those of their inboxes.
class Api::V1::Accounts::Contacts::AppointmentsController < Api::V1::Accounts::Contacts::BaseController
  def index
    conversations = Conversations::PermissionFilterService.new(
      Current.account.conversations.where(contact_id: @contact.id), Current.user, Current.account
    ).perform
    @appointments = Current.account.appointments.where(conversation_id: conversations.select(:id))
                           .includes(:erp_source, :procedures)
                           .order(Appointment.arel_table[:scheduled_for].desc.nulls_last, id: :desc)
    render 'api/v1/accounts/conversations/appointments/show'
  end
end
