# The clinic as arranged in the editor. Everyone on the page reads it;
# administrators and managers save it or restore the default clinic. Open
# maps of the account reload it right away.
class Api::V2::Accounts::VirtualClinic::LayoutsController < Api::V1::Accounts::BaseController
  SEAT = %i[name sheet x y].freeze

  def show
    authorize :virtual_clinic, :show?
    render json: payload(Current.account.virtual_clinic_layout)
  end

  def update
    authorize :virtual_clinic, :update_layout?
    record = Current.account.virtual_clinic_layout || Current.account.build_virtual_clinic_layout
    record.assign_attributes(layout: layout_params, updated_by: Current.user)
    if record.save
      broadcast_change
      render json: payload(record)
    else
      render json: { message: record.errors[:layout].join(' '), errors: record.errors[:layout] }, status: :unprocessable_entity
    end
  end

  def destroy
    authorize :virtual_clinic, :update_layout?
    Current.account.virtual_clinic_layout&.destroy!
    broadcast_change
    render json: payload(nil)
  end

  private

  def layout_params
    params.require(:layout).permit(
      floors: [], walls: [], items: %i[sprite x y flip sortY],
      rooms: ::VirtualClinic::LayoutValidator::ROOMS,
      team: ::VirtualClinic::Persona::KEYS.index_with { SEAT }
    ).to_h
  end

  def payload(record)
    { layout: record&.layout, updated_at: record&.updated_at, updated_by: record&.updated_by&.available_name }
  end

  def broadcast_change
    ActionCable.server.broadcast("virtual_clinic_#{Current.account.id}",
                                 { event: 'virtual_clinic.layout', data: { account_id: Current.account.id, user_id: Current.user.id } })
  end
end
