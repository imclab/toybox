require 'sinatra'
#require 'sinatra/json'
#require 'json'

TRACK_BASE="/tmp/trackserver"

get '/tracks/:id' do
  trackfile = File.join(TRACK_BASE, "#{params[:id]}.json")

  if File.exist?(trackfile)
    # deserializing and serializing again seems stupid
    set :content_type, "application/json"
    File.read(trackfile)
  else
    404
  end
end

get '/downloads/:name' do
  mp3 = File.join(TRACK_BASE, "#{params[:name]}")

  if File.exist?(mp3)
    content_type "application/octet-stream"
    File.read(mp3)
  else
    404
  end
end