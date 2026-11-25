# The LimeZu art of the Clínica virtual. The pack is licensed to Auris but
# can never be redistributed, so it stays out of the (public) repository:
# in development it is read from VIRTUAL_CLINIC_ASSETS_PATH, in production
# from private Active Storage blobs uploaded with
# `rails "virtual_clinic:upload_assets[/path/to/clinica-virtual-selecao]"`.
class VirtualClinic::AssetStore
  PATH_FORMAT = %r{\A[0-9a-z_]+/[0-9A-Za-z_]+\.png\z}
  KEY_PREFIX = 'virtual_clinic/'.freeze
  VERSION_KEY = 'VIRTUAL_CLINIC::ASSETS_VERSION'.freeze

  def self.read(path)
    return unless PATH_FORMAT.match?(path)

    root = ENV.fetch('VIRTUAL_CLINIC_ASSETS_PATH', nil)
    return read_file(root, path) if root.present?

    ActiveStorage::Blob.find_by(key: "#{KEY_PREFIX}#{path}")&.download
  end

  def self.read_file(root, path)
    file = File.join(File.expand_path(root), path)
    File.binread(file) if File.file?(file)
  end

  # Every file of the pack the clinic can use (the editor catalog).
  def self.list
    root = ENV.fetch('VIRTUAL_CLINIC_ASSETS_PATH', nil)
    paths = if root.present?
              Dir.glob('*/*.png', base: File.expand_path(root))
            else
              ActiveStorage::Blob.where('key LIKE ?', "#{KEY_PREFIX}%").pluck(:key).map { |key| key.delete_prefix(KEY_PREFIX) }
            end
    paths.grep(PATH_FORMAT).sort
  end

  # Uploads every PNG of the selection folder, replacing what is there.
  def self.upload(dir)
    Dir.glob('*/*.png', base: dir).grep(PATH_FORMAT).each do |path|
      ActiveStorage::Blob.find_by(key: "#{KEY_PREFIX}#{path}")&.purge
      ActiveStorage::Blob.create_and_upload!(io: File.open(File.join(dir, path)), filename: File.basename(path),
                                             content_type: 'image/png', key: "#{KEY_PREFIX}#{path}")
    end
    store_version
  end

  # Changes with every upload. The page puts it in the art URLs, so browsers
  # keep the art cached until new art is uploaded, without a deploy.
  def self.version
    root = ENV.fetch('VIRTUAL_CLINIC_ASSETS_PATH', nil)
    return local_version(File.expand_path(root)) if root.present?

    Redis::Alfred.get(VERSION_KEY) || store_version
  end

  # In development: the newest file of the pack.
  def self.local_version(root)
    Dir.glob('*/*.png', base: root).map { |path| File.mtime(File.join(root, path)) }.max.to_i.to_s
  end

  # The time of the latest upload, kept in Redis so the blobs table is not
  # scanned on every page load.
  def self.store_version
    version = ActiveStorage::Blob.where('key LIKE ?', "#{KEY_PREFIX}%").maximum(:created_at).to_i.to_s
    Redis::Alfred.set(VERSION_KEY, version)
    version
  end
end
