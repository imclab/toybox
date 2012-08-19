require 'macaddr'
require 'json'
require 'timeout'

require './lib/publisher'
require './lib/generator'

$stdout.sync = true

# Arguments
serial_device_prefix = ARGV[0] || "/dev/ttyACM"
device_id = ARGV[1] || MacAddr.address

# Constants
generator_type = :serial_port # or :static

# Counters
sequence_id = 1
serial_index = 0

# ZMQ Publisher
publisher = Publisher.new
sleep(2) # Delay so clients can reconnect before attach event

# Statuses
connected = false

def get_device(prefix, serial_index)
  serial_devices = Dir.glob(prefix + "*")
  raise Errno::ENODEV if serial_devices.empty?
  serial_devices[serial_index % serial_devices.length]
end

while true
  begin
    if generator_type == :serial_port
      serial_device = get_device(serial_device_prefix, serial_index)
      serial_index += 1
    end

    generator = Generator.new(generator_type, serial_device)
    puts "Attached to serial device: #{serial_device} ..."

    publisher.publish("attach", device_id)
    puts "Registered device id: " + device_id

    connected = true

    while true
      times = generator.next do |command|
        message = {
          sequenceId:   sequence_id,
          command:      command,
          deviceId:     device_id,
          timestamp:    (Time.now.to_f * 1000).floor
        }

        publisher.publish("command", message.to_json)
        sequence_id += 1
      end

      generator.get_signals
      sleep(0.1)
    end
  rescue Errno::EIO, Errno::ENODEV, Errno::ENOENT => e
    if connected
      puts "Detached serial device: #{serial_device} ..."
      publisher.publish("detach", device_id)
      connected = false
    end

    sleep 0.5
  end
end
