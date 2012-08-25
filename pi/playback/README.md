# toybox:pi:playback

An asynchronous playback wrapper around mplayer.

## Usage

Drop it somewhere in your load path.

```ruby
require 'mplayer'

Mplayer::play('button1')
Mplayer::stop()
Mplayer::play('button2')
Mplayer::play('button3')
Mplayer::set_speed(0.75)
Mplayer::set_volume(50)
Mplayer::stop()
Mplayer::kill()
```

## Notes/Caveats

* Playbacks are asynchronous. Mplayer::play() WILL return immediately, and playback will continue in the background until you Mplayer::stop().
* Only one audio stream can be played at a time. New plays will stop any previously playing track and start the new one.
* It plays back tracks from ```/tmp/tracks/#{name}.mp3```
* This module is currently hard-coded for the audio device on the Raspberry Pi, so if it doesn't work for you, remove the references to "-ao alsa..." in the ```start_mplayer()``` method.
* Despite tweaking the ```-key-fifo-size``` parameter it still seems that commands are buffered for a while. So if you submit a bunch of commands to play tracks, they may backlog somewhat rather than just overwriting each other (but will still return immediately).

### IMPORTANT!!!
* Make sure you ```Mplayer::kill()``` before your application terminates, as the mplayer processes are detached and will not be cleaned up like regular child processes when the parent exits.
* 100ms seems to be able the minimum safe interval between commands for mplayer, so don't try to send speed/volume changes any faster than 10Hz or you will end up with audio artifacts at best and no output and crashes at worst.
