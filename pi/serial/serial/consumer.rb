require './lib/consumer'

consumer = Consumer.new("tcp://127.0.0.1:2101", %w(attach command))

while message = consumer.consume
  topic, message = message
  puts "Received #{topic}: #{message}"
end
