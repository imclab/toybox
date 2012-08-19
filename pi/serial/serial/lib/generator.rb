require 'serialport'

class Generator
  SEPARATOR = "\r\n"

  def initialize(type=:serial_port, device=nil)
    @buffer = ""
    @type = type
    if type == :serial_port
      @sp = SerialPort.new(device, 9600)
      @sp.read_timeout = -1
    end
  end

  def next(&block)
    @buffer += read

    while index = @buffer.index(SEPARATOR)
      yield @buffer.slice!(0, index+SEPARATOR.length).strip
    end
  end

  def read
    if @type == :serial_port
      @sp.read
    else
      sleep(0.2+rand*3)
      %w(button0 button1 microphone).map do |el|
        ["#{el}:on\r\n", "#{el}:off\r\n"]
      end.flatten.shuffle.first
    end
  end

  def get_signals
    @sp.get_signals if @type == :serial_port
  end

  def close
    @sp.close if @type == :serial_port
  end
end
