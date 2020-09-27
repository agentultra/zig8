const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

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
        0x1000 => { // jump
            pc = opcode & 0x0FFF;
        },
        0x2000 => { // call
            stack[sp] = pc;
            sp += 1;
            pc = opcode & 0x0FFF;
        },
        0x3000 => { // jumpif
            const i: u8 = (opcode & 0x0F00) >> 8;
            const kk: u8 = opcode & 0x00FF;
            if (V[i] == kk) {
                pc += 4;
            } else {
                pc += 2;
            }
        },
        0x4000 => { // skip next if
            const i: u8 = (opcode & 0x0F00) >> 8;
            const kk: u8 = opcode & 0x00FF;
            if (V[i] != kk) {
                pc += 4;
            } else {
                pc += 2;
            }
        },
        0x5000 => { // skip if registers equal
            const i: u8 = (opcode & 0x00F0) >> 4;
            const j: u8 = (opcode & 0x0F00) >> 8;
            if (V[i] == V[j]) {
                pc += 4;
            } else {
                pc += 2;
            }
        },
        0x6000 => {
            const i: u8 = (opcode & 0x0F00) >> 8;
            const kk: u8 = opcode & 0x00FF;
            V[i] = kk;
            pc += 2;
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
                0x0000 => { // clear screen
                    for (gfx) |*px| {
                        px.* = 0;
                    }
                    pc += 2;
                },
                0x000E => { // return
                    pc = stack[sp];
                    sp -= 1;
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
