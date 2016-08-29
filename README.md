# midi2pico
A Midi to PICO-8 converter.

Requires [MIDI.lua](http://www.pjb.com.au/comp/lua/MIDI.html)

## Usage:
```
lua midi2pico.lua somesong.mid songdata.p8 --speed=(somenumber)
```
Does not write a complete p8 file, only `__sfx__` and `__music__` data  
Various options are available, run the program with no arguments to get help.

