#!/usr/bin/env ruby

require 'rubygems'
require 'net/http'
require 'json'
require 'optparse'
require 'fileutils'
require 'systemu'

# constants
JSON_ENDPOINT='http://sctoybox.herokuapp.com'
LOCAL_STORAGE='/tmp/toybox'
SLEEP_PERIOD=60

# derived values
@track_url_prefix = "#{JSON_ENDPOINT}/tracks/"
@track_cachefile = "#{LOCAL_STORAGE}/cache.json"

# Logging/debugging
@debug = false
def log(msg)
  @debug and STDERR.puts(msg)
end

# Read/create the cache file
def load_track_cache()
  track_cache = nil

  if File.exist?(@track_cachefile)
    log("#{@track_cachefile} exists, loading")
    track_cache = JSON.parse(File.read(@track_cachefile))
  else
    log("Creating #{@track_cachefile}")
    track_cache = {}
    File.open(@track_cachefile, 'w') do |f|
      f.write(JSON.dump(track_cache))
    end
  end

  return track_cache
end

# Save the new cache file
def save_track_cache(track_cache)
  log("Saving cache file #{@track_cachefile}")
  File.open(@track_cachefile, 'w') do |f|
    f.write(JSON.dump(track_cache))
  end
end

# format a track listing for the cache file
def prepare_cache(tracks)
  cache = {}
  tracks.each do |track|
    cache[track['event']] = track['url']
  end
  cache
end

# fetch location header from 302 response
def get_redirect(stream_url)
  uri = URI.parse(stream_url)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE  # I know, I know

  request = Net::HTTP::Get.new(uri.request_uri)
  response = http.request(request)
  response['location']
end

# Download tracks
# Right now we just obliterate whatever was there, no atomic switch.
def download_tracks(queue)
  if queue.empty?
    log("No tracks to download")
    return
  else
    queue.each do |event, track|
      log("Downloading #{track}")
      download = Net::HTTP.get(URI.parse(get_redirect(track)))
      event_mp3 = File.join(LOCAL_STORAGE, "#{event}.mp3")
      log("Storing #{track} of #{download.length} bytes in #{event_mp3}")
      File.open(event_mp3, 'w') do |f|
        f.write(download)
      end
    end
  end
end

# Parse output from ifconfig / etc
def parse(output)
  re = %r/(?:[^:\-]|\A)(?:[0-9A-F][0-9A-F][:\-]){5}[0-9A-F][0-9A-F](?:[^:\-]|\Z)/io

  lines = output.split(/\n/)
  candidates = lines.select{|line| line =~ re}
  raise 'no mac address candidates' unless candidates.first
  candidates.map!{|c| c[re].strip}

  maddr = candidates.first
  raise 'no mac address found' unless maddr

  maddr.strip!
  maddr.instance_eval{ @list = candidates; def list() @list end }
  maddr
end

# Detect mac address
def mac_address()
  re = %r/[^:\-](?:[0-9A-F][0-9A-F][:\-]){5}[0-9A-F][0-9A-F][^:\-]/io
  cmds = '/sbin/ifconfig', '/bin/ifconfig', 'ifconfig', 'ipconfig /all', 'cat /sys/class/net/*/address'

  null = test(?e, '/dev/null') ? '/dev/null' : 'NUL'

  output = nil
  cmds.each do |cmd|
    status, stdout, stderr = systemu(cmd) rescue next
    next unless stdout and stdout.size > 0
    output = stdout and break
  end
  raise "all of #{ cmds.join ' ' } failed" unless output

  parse(output)
end

# Poor-man's event machine
def main_loop()
  # Startup stuff
  File.directory?(LOCAL_STORAGE) || FileUtils.mkdir(LOCAL_STORAGE)

  while(true) do
    # Pull down the latest version of the track listing
    track_url = "#{@track_url_prefix}#{mac_address}.json"
    log("Pulling down track cache from #{track_url}")
    begin
      response = Net::HTTP.get_response(URI.parse(track_url))
      unless ["304", "200"].include? response.code
        sleep(SLEEP_PERIOD)
        next
      end
    rescue URI::InvalidURIError
      log("Invalid URI: #{track_url}")
      next
    end
    track_listing = JSON.parse(response.body)
    # Read/create the cache file
    track_cache = load_track_cache()

    # Compare the remote listing to our cache
    download_queue = {}
    track_listing.each do |track|
      event = track['event']
      track_url = track['url']
      # If we have that event in the cache, check it is fresh
      if track_cache[event] and track_cache[event] == track_url
        next
      else
        track_cache[event] = download_queue[event] = track_url
      end
    end

    # If we have to download new tracks, do it now.
    # Then save the track listing to the local cache.
    download_tracks(download_queue)
    save_track_cache(prepare_cache(track_listing))

    # And now sleep for a minute
    log("Sleeping for #{SLEEP_PERIOD} seconds")
    sleep(SLEEP_PERIOD)
  end
end

if __FILE__ == $PROGRAM_NAME
  option_parser = OptionParser.new do |opts|
    opts.on('-v', '--verbose', 'Enable verbose (debugging) output') do |v|
      @debug = true
    end
  end
  option_parser.parse!(ARGV)
  
  main_loop()
end
