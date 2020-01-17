# midi2pico
A Midi to PICO-8 converter.

Requires [MIDI.lua](http://www.pjb.com.au/comp/lua/MIDI.html) [(direct link)](http://www.pjb.com.au/comp/lua/MIDI.lua)
```
# luarocks install midi
```

## Usage:
```
lua midi2pico.lua somesong.mid songdata.p8
```
Various options are available, run the program with no arguments to get help.

## Tips:
* Mute problematic channels with `--mute`, timidity's `--mute` argument can aid in finding problematic channels.
* Halve the time division to possibly allow more mid-note effects.
* Drums are problematic. Use `--dshift` to shift drum pitch, `--drumvol=n` to change drum volume, or `--mute=10` to remove drums all together.
