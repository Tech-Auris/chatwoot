require 'rails_helper'

RSpec.describe VirtualClinicChannel do
  let(:account) { create(:account, virtual_clinic_enabled: true) }
  let(:user) { create(:user, account: account, name: 'Fábio', display_name: 'Fábio') }

  before { stub_connection }

  def join(target = account)
    subscribe(user_id: user.id, pubsub_token: user.pubsub_token, account_id: target.id, session: 'tab-1')
  end

  it 'streams the account map when the Clínica virtual is released' do
    join
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("virtual_clinic_#{account.id}")
  end

  it 'rejects accounts without the Clínica virtual' do
    join(create(:account).tap { |other| create(:account_user, account: other, user: user) })
    expect(subscription).to be_rejected
  end

  it 'rejects a wrong pubsub token' do
    subscribe(user_id: user.id, pubsub_token: 'nope', account_id: account.id)
    expect(subscription).to be_rejected
  end

  it 'shares the avatar position with the rest of the account' do
    join
    expect { perform :move, x: 120.7, y: '88', direction: 'left', moving: true, since: 1_700_000_000_000 }
      .to have_broadcasted_to("virtual_clinic_#{account.id}")
      .with(event: 'virtual_clinic.presence',
            data: { user_id: user.id, name: 'Fábio', session: 'tab-1', x: 120, y: 88, moving: true, direction: 'left',
                    sitting: false, compact: false, avatar: nil, since: 1_700_000_000_000 })
  end

  it 'shares the look made in the avatar editor, and drops anything else' do
    join
    look = { 'body' => 'Body_32x32_07', 'eyes' => 'Eyes_32x32_02', 'outfit' => 'Outfit_05_32x32_02', 'hair' => 'Hairstyle_04_32x32_03' }
    expect { perform :move, x: 1, y: 2, avatar: look }
      .to have_broadcasted_to("virtual_clinic_#{account.id}")
      .with(hash_including(data: hash_including(avatar: look)))
    expect { perform :move, x: 1, y: 2, avatar: look.merge('hair' => '../secret') }
      .to have_broadcasted_to("virtual_clinic_#{account.id}")
      .with(hash_including(data: hash_including(avatar: nil)))
  end

  it 'shares whether the avatar is sitting' do
    join
    expect { perform :move, x: 1, y: 2, direction: 'left', sitting: true, compact: true }
      .to have_broadcasted_to("virtual_clinic_#{account.id}")
      .with(hash_including(data: hash_including(sitting: true, compact: true)))
  end

  it 'falls back to facing down on an unknown direction' do
    join
    expect { perform :move, x: 1, y: 2, direction: 'sideways' }
      .to have_broadcasted_to("virtual_clinic_#{account.id}")
      .with(hash_including(data: hash_including(direction: 'down', moving: false)))
  end

  it 'tells the others when the user leaves the map' do
    join
    expect { unsubscribe }.to have_broadcasted_to("virtual_clinic_#{account.id}")
      .with(event: 'virtual_clinic.presence', data: { user_id: user.id, name: 'Fábio', session: 'tab-1', left: true })
  end
end
