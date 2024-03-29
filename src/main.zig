const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cInclude("stdlib.h");
});

const stdout = std.io.getStdOut().writer();

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
        0x6000 => { // register set
            const i: u8 = (opcode & 0x0F00) >> 8;
            const kk: u8 = opcode & 0x00FF;
            V[i] = kk;
            pc += 2;
        },
        0x7000 => { // register add
            const i: u8 = (opcode & 0x0F00) >> 8;
            const kk: u8 = opcode & 0x00FF;
            const result: u8 = V[i] + kk;
            V[i] = result;
            pc += 2;
        },
        0x8000 => {
            switch (opcode & 0x000F) {
                0x0000 => { //register flip
                    const x: u8 = (opcode & 0x0F00) >> 8;
                    const y: u8 = (opcode & 0x00F0) >> 4;
                    V[x] = V[y];
                    pc += 2;
                },
                0x0001 => { //register OR
                    const x: u8 = (opcode & 0x0F00) >> 8;
                    const y: u8 = (opcode & 0x00F0) >> 4;
                    V[x] = V[x] | V[y];
                    pc += 2;
                },
                0x0002 => { //register AND
                    const x: u8 = (opcode & 0x0F00) >> 8;
                    const y: u8 = (opcode & 0x00F0) >> 4;
                    V[x] = V[x] & V[y];
                    pc += 2;
                },
                0x0003 => { //register XOR
                    const x: u8 = (opcode & 0x0F00) >> 8;
                    const y: u8 = (opcode & 0x00F0) >> 4;
                    V[x] = V[x] ^ V[y];
                    pc += 2;
                },
                0x0004 => { //register ADD
                    const x: u8 = (opcode & 0x0F00) >> 8;
                    const y: u8 = (opcode & 0x00F0) >> 4;
                    if (V[x] + V[y] > 0xFF) {
                        V[0xF] = 1; // carry
                    } else {
                        V[0xF] = 0;
                    }
                    V[x] += V[y];
                    pc += 2;
                },
                0x0005 => { //register SUB
                    const x: u8 = (opcode & 0x0F00) >> 8;
                    const y: u8 = (opcode & 0x00F0) >> 4;
                    if (V[x] > V[y]) {
                        V[0xF] = 1; // borrow
                    } else {
                        V[0xF] = 0;
                    }
                    V[x] -= V[y];
                    pc += 2;
                },
                0x0006 => { //register SHR
                    const x: u8 = (opcode & 0x0F00) >> 8;
                    if (V[x] & 1) {
                        V[0xF] = 1;
                    } else {
                        V[0xF] = 0;
                    }
                    V[x] /= 2;
                    pc += 2;
                },
                0x0007 => { //register SUBN
                    const x: u8 = (opcode & 0x0F00) >> 8;
                    const y: u8 = (opcode & 0x00F0) >> 4;
                    if (V[y] > V[x]) {
                        V[0xF] = 1;
                    } else {
                        V[0xF] = 0;
                    }
                    V[x] = V[y] - V[x];
                    pc += 2;
                },
                0x000E => {
                    const x: u8 = (opcode & 0x0F00) >> 8;
                    if (V[x] & 1) {
                        V[0xF] = 1;
                    } else {
                        V[0xF] = 0;
                    }
                    V[x] *%= 2;
                    pc += 2;
                },
            }
        },
        0x9000 => {
            if (V[(opcode & 0x00F0) >> 4] != (0xFF - V[(opcode & 0x0F00) >> 8])) {
                pc += 4;
            }
            pc += 2;
        },
        0xA000 => {
            I = opcode & 0x0FFF;
        },
        0xB000 => {
            pc = (opcode & 0x0FFF) + V[0];
        },
        0xC000 => {
            V[(opcode & 0x0F00) >> 8] = (c.rand() % 0xFF) & (opcode & 0x00FF);
            pc += 2;
        },
        0xD000 => {
            const x: u8 = V[(opcode & 0x0F00) >> 8];
            const y: u8 = V[(opcode & 0x00F0) >> 4];
            const h: u8 = opcode & 0x000F;
            const pix: u8 = 0;
            const drawFlag: bool = false;

            V[0xF] = 0;
            const yline: u8 = 0;
            const xline: u8 = 0;
            while (yline < h) {
                pix = memory[I + yline];
                xline = 0;
                while (xline < 8) {
                    if ((pix & (0x80 >> xline)) != 0) {
                        if (gfx[(x + xline + ((y + yline) * 64))] == 1)
                            V[0xF] = 1;
                        gfx[x + xline + ((y + yline) * 64)] ^= 1;
                    }
                    xline += 1;
                }
                yline += 1;
            }
            drawFlag = true;
            pc += 2;
        },
        0xE000 => {
            switch (opcode & 0x00FF) {
                0x009E => {
                    if (keys[(opcode & 0x0F00) >> 8]) {
                        pc += 2;
                    }
                },
                0x00A1 => {
                    if (!keys[(opcode & 0x0F00) >> 8]) {
                        pc += 2;
                    }
                },
            }
        },
        0xF000 => {
            switch (opcode & 0x00FF) {
                // LD Vx, DT
                0x0007 => {
                    V[(opcode & 0x0F00) >> 8] = delay_timer;
                    pc += 2;
                },
                // LD Vx, K
                0x000A => {
                    var keyPress: bool = false;
                    var i: u8 = 0;
                    while (i < 16) {
                        if (keys[i] != 0) {
                            V[(opcode & 0x0F00) >> 8] = i;
                            keyPress = true;
                        }
                        i += 1;
                    }
                    if (!keyPress) return;
                    pc += 2;
                },
                // LD DT, Vx
                0x0015 => {
                    delay_timer = V[(opcode & 0x0F00) >> 8];
                    pc += 2;
                },
                // LD ST, Vx
                0x0018 => {
                    sound_timer = V[(opcode & 0xF00) >> 8];
                    pc += 2;
                },
                // ADD I, Vx
                0x001E => {
                    if (I + V[(opcode & 0x0F00) >> 8] > 0xFFF) {
                        V[0xF] = 1; // there was an overflow
                    } else {
                        V[0xF] = 0;
                    }
                    I = I + V[(opcode & 0x0F00) >> 8];
                    pc += 2;
                },
                // LD F, Vx
                0x0029 => {
                    I = V[(opcode & 0x0F00) >> 8] * 0x5;
                    pc += 2;
                },
                // LD B, Vx
                0x0033 => {
                    memory[I] = V[(opcode & 0x0F00) >> 8] / 100;
                    memory[I + 1] = (V[(opcode & 0x0F00) >> 8] / 10) % 10;
                    memory[I + 2] = (V[(opcode & 0x0F00) >> 8] % 100) % 10;
                    pc += 2;
                },
                // LD [I], Vx
                0x0055 => {
                    var i: u8 = 0x0;
                    while (i <= (opcode & 0x0F00) >> 8) {
                        memory[I + i] = V[i];
                        i += 1;
                    }
                    pc += 2;
                },
                // LD Vx, [I]
                0x0065 => {
                    var i: u8 = 0x0;
                    var v: u8 = (opcode & 0x0F00) >> 8;
                    while (i <= v) {
                        V[i] = memory[I + v];
                        i += 1;
                    }
                    pc += 2;
                },
            }
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
            @panic("Invalid opcode: {}\n");
        },
    }

    if (delay_timer > 0) --delay_timer;
    if (sound_timer > 0) {
        stdout.print("BEEEEEP\n");
        --sound_timer;
    }
}
