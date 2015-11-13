json.array!(@contacts) do |contact|
  json.extract! contact, :id, :name, :email
  json.url contact_url(contact, format: :json)
end
