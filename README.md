# zig8

A [Chip-8](http://devernay.free.fr/hacks/chip8/C8TECH10.HTM "Chip-8
reference") emulator written in [ziglang](https://ziglang.org/) in
order to learn Zig and have fun.

## Building

Currently built with Zig `0.15.1`:

  $ zig build -Dinstall

## Running

You give the ROM you want to load as the first argument:

  $ ./zig-out/bin/zig8 data/1-chip8-logo.ch8

When run from the project root, after building, should run an included
test ROM.
