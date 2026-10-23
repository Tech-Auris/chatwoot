json.payload do
  json.array! @audiences do |audience|
    json.partial! 'api/v1/models/audience', formats: [:json], resource: audience
  end
end
json.meta do
  json.total_count @audiences.size
  json.downloads_last_30_days @stats[:downloads]
  json.campaigns_last_30_days @stats[:campaigns]
  json.last_download_at @stats[:last_download_at]
end
