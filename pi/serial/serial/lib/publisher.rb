require 'ffi-rzmq'

class Publisher
  ZCTX = ZMQ::Context.new(1)

  def initialize
    @zmq_addr = "tcp://127.0.0.1:2101"
    bind
  end

  def bind
    @zmq_socket = ZCTX.socket(ZMQ::PUB)
    @zmq_socket.setsockopt(ZMQ::LINGER, 1)
    @zmq_socket.bind(@zmq_addr)
    puts "Publishing events to ZMQ: #{@zmq_addr}"
  end

  def valid?(rc)
    if !(valid = ZMQ::Util.resultcode_ok?(rc))
      STDERR.puts "Operation failed, errno [#{ZMQ::Util.errno}] description [#{ZMQ::Util.error_string}]"
    end

    valid
  end

  def publish(topic, message, retried=false)
    success = false

    if valid?(@zmq_socket.send_string(topic, ZMQ::SNDMORE))
      if valid?(@zmq_socket.send_string(message))
        success = true
        puts "==> Published to 0mq [#{topic}/#{message}]"
      end
    end

    if !success and !retried
      puts "Error publishing, rebinding..."
      bind
      public(topic,message,true)
    elsif retried
      puts "Error publishing, aborting..."
      exit(0)
    else
      true
    end
  end
end
