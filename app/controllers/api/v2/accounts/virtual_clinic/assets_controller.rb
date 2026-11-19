# One PNG of the clinic art, only for logged-in users of released accounts.
class Api::V2::Accounts::VirtualClinic::AssetsController < Api::V1::Accounts::BaseController
  def show
    authorize :virtual_clinic, :show?
    data = ::VirtualClinic::AssetStore.read(params[:path])
    return head :not_found if data.nil?

    expires_in 1.week, public: false
    send_data data, type: 'image/png', disposition: 'inline'
  end
end
