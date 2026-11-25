require 'rails_helper'

RSpec.describe VirtualClinic::AssetStore do
  let(:png) { Rails.root.join('spec/assets/avatar.png').binread }
  let(:assets_dir) { Dir.mktmpdir }

  before do
    Redis::Alfred.delete(described_class::VERSION_KEY)
    FileUtils.mkdir_p(File.join(assets_dir, '1_recepcao'))
    File.binwrite(File.join(assets_dir, '1_recepcao', 'relogio.png'), png)
  end

  after { FileUtils.remove_entry(assets_dir) }

  describe '.version' do
    around { |example| with_modified_env(VIRTUAL_CLINIC_ASSETS_PATH: nil) { example.run } }

    it 'changes when new art is uploaded' do
      first = Time.zone.local(2026, 11, 20, 12)
      travel_to(first) { described_class.upload(assets_dir) }
      expect(described_class.version).to eq(first.to_i.to_s)

      second = Time.zone.local(2026, 11, 24, 9)
      travel_to(second) { described_class.upload(assets_dir) }
      expect(described_class.version).to eq(second.to_i.to_s)
    end

    it 'is rebuilt from the stored art when Redis lost it' do
      uploaded_at = Time.zone.local(2026, 11, 20, 12)
      travel_to(uploaded_at) { described_class.upload(assets_dir) }
      Redis::Alfred.delete(described_class::VERSION_KEY)

      expect(described_class.version).to eq(uploaded_at.to_i.to_s)
      expect(Redis::Alfred.get(described_class::VERSION_KEY)).to eq(uploaded_at.to_i.to_s)
    end

    it 'follows the newest file of the local pack in development' do
      changed_at = Time.zone.local(2026, 11, 22, 15).to_time
      File.utime(changed_at, changed_at, File.join(assets_dir, '1_recepcao', 'relogio.png'))

      with_modified_env VIRTUAL_CLINIC_ASSETS_PATH: assets_dir do
        expect(described_class.version).to eq(changed_at.to_i.to_s)
      end
    end
  end
end
