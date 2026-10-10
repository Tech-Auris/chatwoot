json.payload do
  json.array! @pixels, partial: 'pixel', as: :pixel
end
