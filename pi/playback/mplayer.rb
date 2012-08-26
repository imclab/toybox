# simple wrapper around mplayer so that we can trigger track playback and some
# basic maninpulation of the sound output

module Mplayer
  FIFO_PATH = '/tmp/sound'
  TRACK_BASE = '/tmp/toybox'

  extend self

  # Play a track, potentially stopping another while playing.
  def play(event)
    # Determine the path to the event mp3 and spawn mplayer to play it.
    file = File.expand_path(File.join(TRACK_BASE, "#{event}.mp3"))

    if (!File.exist?(file))
      puts "No file to play: #{file}"
      return false
    end

    # Load (play) the file after stopping any previous one
    stop()
    %x{#{echo()} loadfile #{file} > #{fifo()}} if running?
  end

  # Stop playing the current track.
  def stop()
    if running?
      # stop sound then reset parameters in case they were previously changed
      %x{#{echo()} stop > #{fifo()}}
      set_speed(1.0)
      set_volume(100)
    end
  end

  # Change the speed by echoing a command to the mplayer input FIFO
  # Expects a floating point number where 1.0 is full speed.
  def set_speed(speed)
    %x{#{echo()} speed_set #{speed} > #{fifo()}} if running?
  end

  # Change the volume by echoing a command to the mplayer input FIFO
  # Expects a value 0 - 100 (as a percentage of full volume)
  def set_volume(volume)
    %x{#{echo()} volume #{volume} 1 > #{fifo()}} if running?
  end

  # Pauses or unpauses the track
  # WARNING: This is highly unstable, and mplayer usually crashes.
  def toggle_pause()
    %x{#{echo} pause > #{fifo()}} if running?
  end

  # Provide a way to kill the mplayer process
  def kill()
    Process.kill(15, @pid) if running?
  end

  private

  # Check if mplayer is running.
  def running?()
    # If we don't have a PID, it's probably not running. Start it!
    start_mplayer unless @pid

    # Non-blocking wait on the child process.
    # Should be cross-platform compatible
    begin
      return true if Process.wait(@pid, Process::WNOHANG).nil?
    rescue Exception
      # something must have killed it, start it again!
      start_mplayer()
    end
  end

  # Command shortcut to mplayer itself.
  # We split it up so that Process.spawn doesn't run the command in a shell.
  def start_mplayer()
    @pid = Process.spawn(mplayer(),
                  '-softvol',      # software volume mixer
                  '-nocache',      # don't cache anything
                  '-nolirc',       # don't attempt to initialise a LIRC remote
                  '-really-quiet', # no informational messages
                  '-idle',         # run without immediately playing anything
                  '-input',        # listen on a FIFO for commands
                  "file=#{fifo()}",# the FIFO location
                  #'-ao',           # use this audio output
                  #'alsa:device=hw=0.0', # specifically for Raspberry Pi
                  '-key-fifo-size',# limit the number of events we buffer
                  '5'              # ...to 4. This allows stop() to work.
                 )

    # don't care when the process ends... mostly
    Process.detach(@pid)
  end

  # Lazy evaluate creation of the FIFO for mplayer commands
  def fifo()
    if ! File.pipe?(FIFO_PATH)
      # there's no native ruby way to do this?
      %x{#{mkfifo()} #{FIFO_PATH}}
    end
    return FIFO_PATH
  end

  # Find commands and make methods for them
  %w{mkfifo ps mplayer echo}.each do |command|
    eval "
      def #{command}
        @#{command} ||= %x{which #{command}}.chomp
      end
    "
  end
end
