const std = @import("std");
const testing = std.testing;

// Machine

// 0x000-0x1FF - Chip 8 interpreter (contains font set in emu)
// 0x050-0x0A0 - Used for the built in 4x5 pixel font set (0-F)
// 0x200-0xFFF - Program ROM and work RAM

var opcode: u16 = undefined;
var memory: [4096]u8 = undefined; // main memory
var V: [16]u8 = undefined; // registers V1 - VE
var I: u16 = undefined; // index register
var pc: u16 = undefined; // program counter
var stack: [16]u16 = undefined; // program stack
var sp: u16 = undefined; // stack pointer
var gfx: [2048]u8 = undefined; // graphics memory
var keys: [16]u8 = undefined; // keys

var delay_timer: u16 = undefined; // count at 60hz down to zero
var sound_timer: u16 = undefined;

// Emulation API

fn initialize() !void {
    opcode = 0;
    pc = 0x200;
    for (memory) |*loc| {
        loc.* = 0;
    }
    for (V) |*reg| {
        reg.* = 0;
    }
    I = 0;
    for (stack) |*s| {
        s.* = 0;
    }
    sp = 0;
    for (gfx) |*px| {
        px.* = 0;
    }
    for (keys) |*key| {
        key.* = 0;
    }
    delay_timer = 0;
    sound_timer = 0;
}

fn cycle() !void {
    opcode = @as(u16, memory[pc]) << 8 | memory[pc + 1];

    switch (opcode & 0xF000) {
        0xA000 => {
            I = opcode & 0x0FFF;
            pc += 2;
        },
        0x2000 => {
            stack[sp] = pc;
            sp += 1;
            pc = opcode & 0x0FFF;
        },
        0x0004 => {
            if (V[(opcode & 0x00F0) >> 4] > (0xFF - V[(opcode & 0x0F00) >> 8])) {
                V[0xF] = 1; // carry
            } else {
                V[0xF] = 0;
            }
            V[(opcode & 0x0F00) >> 8] += V[(opcode & 0x00F0) >> 4];
            pc += 2;
        },
        0x0000 => {
            switch (opcode & 0x000F) {
                0x0000 => { // 0x00E0: clear the screen
                    // TODO (james): implement this
                },
                0x000E => { // 0x00EE: return from subroutine
                    // TODO (james): implement me!!!
                },
                else => {
                    @panic("Invalid opcode [0x0000]: {}\n");
                },
            }
        },
        else => {
            @panic("Invalid opcode: {}\n", opcode);
        },
    }

    if (delay_timer > 0) --delay_timer;
    if (sound_timer > 0) {
        @print("BEEEEEP\n");
        --sound_timer;
    }
}
