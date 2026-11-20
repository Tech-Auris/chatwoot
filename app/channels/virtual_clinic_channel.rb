# Where everyone is on the Clínica virtual map, Gather-style. Each open map
# sends its avatar position (throttled to 5 per second by the page) and gets
# everybody else's from the account stream. Nothing is stored: a position
# only lives while the page is open.
class VirtualClinicChannel < ApplicationCable::Channel
  DIRECTIONS = %w[up down left right].freeze

  def subscribed
    @user = User.find_by(pubsub_token: params[:pubsub_token], id: params[:user_id])
    @account = @user&.accounts&.find_by(id: params[:account_id])
    return reject unless @account&.virtual_clinic_enabled?

    stream_from stream_name
  end

  def move(data)
    broadcast(x: data['x'].to_i, y: data['y'].to_i, moving: data['moving'] == true,
              direction: DIRECTIONS.include?(data['direction']) ? data['direction'] : 'down')
  end

  def unsubscribed
    broadcast(left: true) if @account
  end

  private

  def stream_name
    "virtual_clinic_#{@account.id}"
  end

  def broadcast(position)
    ActionCable.server.broadcast(stream_name, { event: 'virtual_clinic.presence',
                                                data: { user_id: @user.id, name: @user.available_name, **position } })
  end
end
