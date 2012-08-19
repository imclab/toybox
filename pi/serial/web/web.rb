require 'rubygems'
require 'em-websocket'
require 'em-zeromq'
require 'json'
require 'haml'
require 'sinatra/base'
require 'thin'

require '../../toybox-playback/mplayer.rb'

$stdout.sync = true

EventMachine.run do
  class App < Sinatra::Base
      get '/' do
          haml :index
      end
  end

  CHANNEL = EM::Channel.new

  EventMachine::WebSocket.start(:host => '0.0.0.0', :port => 8080) do |ws|
      ws.onopen {
        sid = CHANNEL.subscribe { |msg| ws.send msg }

        ws.onmessage { |msg|

        }

        ws.onclose {
          CHANNEL.unsubscribe(sid)
        }
      }
  end

  class SubHandler
    def on_readable(socket, parts)
      topic, message = parts.map(&:copy_out_string)

      puts "Got message: #{topic} / #{message}"

      if topic && message
        CHANNEL.push("#{topic}: #{message}")
      end

      if message
        message = JSON.parse(message) rescue nil

        play_sound(topic, message) if message
      end
    end

    def on_writable(socket)

    end

    def play_sound(topic, message)
      begin
        case topic
        when "command"
          command, action, subaction = message["command"].split(":")

          puts "Playing command: #{command}:#{action}:#{subaction}"

          if command == "gyro" && subaction == "on"
            if action == "roll"
              Mplayer.play("gyro_roll")
            elsif action == "pitch"
              Mplayer.play("gyro_pitch")
            end
          elsif action == "on"
            if command != "microphone"
              Mplayer.play(command)
            end
          else
            puts "Ignoring action #{action} for command: #{command}"
          end
        when "attach"
          Mplayer.play("attach")
        when "detach"
          Mplayer.play("detach")
        end
      rescue Exception => e
        puts "Error mplayer: #{e}"
      end
    end
  end

  ctx = EM::ZeroMQ::Context.new(1)
  subscriptions = %w(attach detach command)
  zmq_addr = "tcp://127.0.0.1:2101"

  ctx.socket(ZMQ::SUB, SubHandler.new) do |socket|
    subscriptions.each do |subscription|
      socket.subscribe(subscription)
      puts "Subscribed to #{subscription}"
    end
    socket.connect(zmq_addr)
    puts "Connected to ZMQ: #{zmq_addr}"
  end

  App.run!({:port => 3000})
end