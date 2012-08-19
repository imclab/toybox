require 'ffi-rzmq'

class Consumer

  ZCTX = ZMQ::Context.new(1)

  def initialize(addr, subscriptions=[])
    @zmq_addr = addr
    @zmq_subscriptions = subscriptions
    connect
  end

  def connect
    @zmq_socket = ZCTX.socket(ZMQ::SUB)
    @zmq_socket.setsockopt(ZMQ::LINGER, 1)
    @zmq_subscriptions.each do |subscription|
      @zmq_socket.setsockopt(ZMQ::SUBSCRIBE, subscription)
      puts "Subscribed to #{subscription}"
    end
    @zmq_socket.connect(@zmq_addr)
    puts "Connected to ZMQ: #{@zmq_addr}"
  end

  def valid?(rc)
    if !(valid = ZMQ::Util.resultcode_ok?(rc))
      STDERR.puts "Operation failed, errno [#{ZMQ::Util.errno}] description [#{ZMQ::Util.error_string}]"
    end

    valid
  end

  def consume
    success = false
    topic = ''
    message = ''

    if valid?(@zmq_socket.recv_string(topic))
      if @zmq_socket.more_parts?
        if valid?(@zmq_socket.recv_string(message))
          puts "==> Received message from 0mq [#{topic}/#{message}]"
          success = true
        end
      end
    end

    if !success
      puts "Error consuming, reconnecting..."
      connect
      []
    else
      [topic,message]
    end
  end
end
