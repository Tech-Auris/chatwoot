# Attaches the header image/video/document a template went out with, so the
# conversation shows what the contact received. Every message sent with the
# same media shares one stored file (a blob still attached somewhere is never
# purged), so a campaign stores its image once, not once per contact.
class Whatsapp::TemplateHeaderAttachmentService
  pattr_initialize [:message!, :template!, :header_data!]

  FILE_TYPES = { 'image' => :image, 'video' => :video, 'document' => :file }.freeze
  BLOB_KEY_EXPIRY = 30.days

  def perform
    return if file_type.blank? || source_url.blank?

    message.attachments.create!(account_id: message.account_id, file_type: file_type, file: blob)
  # The template already went out: a missing preview must not fail the send.
  rescue StandardError => e
    Rails.logger.error("Template header attachment failed for message #{message.id}: #{e.message}")
  end

  private

  def file_type
    FILE_TYPES[header_data['media_type'].to_s.downcase]
  end

  def source_url
    @source_url ||= Whatsapp::TemplateProcessorService.custom_header_url(header_data) ||
                    Whatsapp::TemplateProcessorService.template_header_url(template)
  end

  def blob
    ActiveStorage::Blob.find_by(id: Redis::Alfred.get(blob_key)) || upload_blob
  end

  def upload_blob
    downloaded = Down.download(source_url, max_size: 100.megabytes)
    filename = header_data['media_name'].presence || downloaded.original_filename || 'header'
    blob = ActiveStorage::Blob.create_and_upload!(io: downloaded, filename: filename, content_type: downloaded.content_type)
    Redis::Alfred.setex(blob_key, blob.id, BLOB_KEY_EXPIRY)
    blob
  ensure
    downloaded&.close!
  end

  def blob_key
    "whatsapp_template_header_blob:#{Digest::SHA256.hexdigest(source_url)}"
  end
end
