# One PNG of the clinic art, only for logged-in users of released accounts.
class Api::V2::Accounts::VirtualClinic::AssetsController < Api::V1::Accounts::BaseController
  # The editor catalog: every file of the pack the clinic can use.
  def index
    authorize :virtual_clinic, :update_layout?
    render json: { paths: ::VirtualClinic::AssetStore.list }
  end

  def show
    authorize :virtual_clinic, :show?
    data = ::VirtualClinic::AssetStore.read(params[:path])
    return head :not_found if data.nil?

    # The page asks with ?v=<AssetStore.version>, so new art comes with a new URL.
    expires_in 1.year, public: false
    send_data data, type: 'image/png', disposition: 'inline'
  end
end
