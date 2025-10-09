# zig8

A [CHIP-8](http://devernay.free.fr/hacks/chip8/C8TECH10.HTM "Chip-8
reference") emulator written in [ziglang](https://ziglang.org/).

## Goals

- Learn Zig
- Emulator capable of interpreting CHIP-8
- Integrated debugger

## Running

After building/installing `zig` you can run any of the test ROMs in
the `data/` directory or run your own by passing the path to the ROM
file as an argument on the command line:

    > zig8 data/1-chip8-logo.c8

You should see a cool Chip-8 logo screen.

Press `Esc` to quit.

## Keybindings

The CHIP-8 computer has a keypad entry interface that maps to a
QWERTY-keyboard like so:

    Keypad       Keyboard
    +-+-+-+-+    +-+-+-+-+
    |1|2|3|C|    |1|2|3|4|
    +-+-+-+-+    +-+-+-+-+
    |4|5|6|D|    |Q|W|E|R|
    +-+-+-+-+ => +-+-+-+-+
    |7|8|9|E|    |A|S|D|F|
    +-+-+-+-+    +-+-+-+-+
    |A|0|B|F|    |Z|X|C|V|
    +-+-+-+-+    +-+-+-+-+

Most games run well at the default speed.  You can slow down or speed
up the emulator with the `[` and `]` keys respectively if needed.

You can resize the display with `,` and `.` to decrease/increase the
size from the default.

You can swap color palettes with the ````` (backtick) key.

You can toggle the shader effect off if you prefer with `\`.

## Building

You'll need Zig `0.15.1` and SDL2 installed:

    > zig build -Dinstall

That should install `zig8` at `zig-out/bin/zig8`.

## Roadmap

### 1.0

- [ ] Integrated Debugger
  - [ ] Pause execution
  - [ ] Step
  - [ ] Memory Watchers
  - [ ] Display pc, sp, stack, registers
  - [ ] Disassembler (optional)
- [ ] Emulator
  - [x] User-controlled CPU hz
  - [x] Wait for keypress (Fx0A)
  - [x] Retro CRT shader effect
  - [x] CRT effect toggle
  - [x] Cycle video pallets
  - [x] Video scaling
  - [ ] Super-Chip8 (optional)
  - [ ] Quirks
  - [x] Delay Timer
  - [ ] Sound Timer
  - [ ] Input buffer
