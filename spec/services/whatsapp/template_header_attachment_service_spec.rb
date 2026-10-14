require 'rails_helper'

RSpec.describe Whatsapp::TemplateHeaderAttachmentService do
  let(:template) do
    { 'name' => 'oferta', 'components' => [
      { 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => ['https://scontent.whatsapp.net/preview.png'] } }
    ] }
  end
  let(:blank_header) { { 'media_url' => '', 'media_type' => 'image' } }

  before do
    stub_request(:get, 'https://scontent.whatsapp.net/preview.png')
      .to_return(status: 200, body: 'png-bytes', headers: { 'Content-Type' => 'image/png' })
  end

  after { Redis::Alfred.delete("whatsapp_template_header_blob:#{Digest::SHA256.hexdigest('https://scontent.whatsapp.net/preview.png')}") }

  it 'attaches the template image when the operator left the URL blank' do
    message = create(:message)

    described_class.new(message: message, template: template, header_data: blank_header).perform

    attachment = message.attachments.first
    expect(attachment.file_type).to eq('image')
    expect(attachment.file.download).to eq('png-bytes')
  end

  it 'stores the image once for every message sent with it' do
    messages = create_list(:message, 2)

    messages.each { |message| described_class.new(message: message, template: template, header_data: blank_header).perform }

    expect(messages.map { |message| message.attachments.first.file.blob_id }.uniq.size).to eq(1)
    expect(WebMock).to have_requested(:get, 'https://scontent.whatsapp.net/preview.png').once
  end
end
