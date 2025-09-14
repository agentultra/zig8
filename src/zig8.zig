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
pub var gfx: [2048]u8 = undefined; // graphics memory
var keys: [16]u8 = undefined; // keys

var delay_timer: u8 = undefined; // count at 60hz down to zero
var sound_timer: u16 = undefined;

const pixMask: u8 = 0x80;

// Emulation API

pub fn initialize() void {
    opcode = 0;
    pc = 0x200;
    for (&memory) |*loc| {
        loc.* = 0;
    }
    for (0..79) |i| {
        memory[i] = fontset[i];
    }
    for (&V) |*reg| {
        reg.* = 0;
    }
    I = 0;
    for (&stack) |*s| {
        s.* = 0;
    }
    sp = 0;
    for (&gfx) |*px| {
        px.* = 0;
    }
    for (&keys) |*key| {
        key.* = 0;
    }
    delay_timer = 0;
    sound_timer = 0;
}

pub fn cycle() void {
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
            const i: u8 = @intCast((opcode & 0x0F00) >> 8);
            const kk: u8 = @intCast(opcode & 0x00FF);
            if (V[i] == kk) {
                pc += 4;
            } else {
                pc += 2;
            }
        },
        0x4000 => { // skip next if
            const i: u8 = @intCast((opcode & 0x0F00) >> 8);
            const kk: u8 = @intCast(opcode & 0x00FF);
            if (V[i] != kk) {
                pc += 4;
            } else {
                pc += 2;
            }
        },
        0x5000 => { // skip if registers equal
            const i: u8 = @intCast((opcode & 0x00F0) >> 4);
            const j: u8 = @intCast((opcode & 0x0F00) >> 8);
            if (V[i] == V[j]) {
                pc += 4;
            } else {
                pc += 2;
            }
        },
        0x6000 => { // register set
            const i: u8 = @intCast((opcode & 0x0F00) >> 8);
            const kk: u8 = @intCast(opcode & 0x00FF);
            V[i] = kk;
            pc += 2;
        },
        0x7000 => { // register add
            const i: u8 = @intCast((opcode & 0x0F00) >> 8);
            const kk: u8 = @intCast(opcode & 0x00FF);
            const result: u8 = V[i] + kk;
            V[i] = result;
            pc += 2;
        },
        0x8000 => {
            switch (opcode & 0x000F) {
                0x0000 => { //register flip
                    const x: u8 = @intCast((opcode & 0x0F00) >> 8);
                    const y: u8 = @intCast((opcode & 0x00F0) >> 4);
                    V[x] = V[y];
                    pc += 2;
                },
                0x0001 => { //register OR
                    const x: u8 = @intCast((opcode & 0x0F00) >> 8);
                    const y: u8 = @intCast((opcode & 0x00F0) >> 4);
                    V[x] = V[x] | V[y];
                    pc += 2;
                },
                0x0002 => { //register AND
                    const x: u8 = @intCast((opcode & 0x0F00) >> 8);
                    const y: u8 = @intCast((opcode & 0x00F0) >> 4);
                    V[x] = V[x] & V[y];
                    pc += 2;
                },
                0x0003 => { //register XOR
                    const x: u8 = @intCast((opcode & 0x0F00) >> 8);
                    const y: u8 = @intCast((opcode & 0x00F0) >> 4);
                    V[x] = V[x] ^ V[y];
                    pc += 2;
                },
                0x0004 => { //register ADD
                    const x: u8 = @intCast((opcode & 0x0F00) >> 8);
                    const y: u8 = @intCast((opcode & 0x00F0) >> 4);
                    const xy: u16 = x + y;
                    if (xy > 0xFF) {
                        V[0xF] = 1; // carry
                    } else {
                        V[0xF] = 0;
                    }
                    V[x] = @intCast((xy & 0x00FF) >> 8);
                    pc += 2;
                },
                0x0005 => { //register SUB
                    const x: u8 = @intCast((opcode & 0x0F00) >> 8);
                    const y: u8 = @intCast((opcode & 0x00F0) >> 4);
                    if (V[x] > V[y]) {
                        V[0xF] = 1; // borrow
                    } else {
                        V[0xF] = 0;
                    }
                    V[x] = x - y;
                    pc += 2;
                },
                0x0006 => { //register SHR
                    const x: u8 = @intCast((opcode & 0x0F00) >> 8);
                    if (V[x] & 1 == 1) {
                        V[0xF] = 1;
                    } else {
                        V[0xF] = 0;
                    }
                    V[x] /= 2;
                    pc += 2;
                },
                0x0007 => { //register SUBN
                    const x: u8 = @intCast((opcode & 0x0F00) >> 8);
                    const y: u8 = @intCast((opcode & 0x00F0) >> 4);
                    if (V[y] > V[x]) {
                        V[0xF] = 1;
                    } else {
                        V[0xF] = 0;
                    }
                    V[x] = V[y] - V[x];
                    pc += 2;
                },
                0x000E => {
                    const x: u8 = @intCast((opcode & 0x0F00) >> 8);
                    if (V[x] & 1 == 1) {
                        V[0xF] = 1;
                    } else {
                        V[0xF] = 0;
                    }
                    V[x] *%= 2;
                    pc += 2;
                },
                else => {
                    @panic("Invalid opcode [0x0800]: {}\n");
                },
            }
        },
        0x9000 => {
            if (V[(opcode & 0x00F0) >> 4] != (0xFF - V[(opcode & 0x0F00) >> 8])) {
                pc += 4;
            }
            pc += 2;
        },
        0xB000 => {
            pc = (opcode & 0x0FFF) + V[0];
        },
        0xC000 => {
            const r: u8 = @intCast(@mod(c.rand(), 0xFF));
            const v: u8 = @intCast(opcode & 0x00FF);
            V[(opcode & 0x0F00) >> 8] = r & v;
            pc += 2;
        },
        0xD000 => {
            const x: u8 = V[(opcode & 0x0F00) >> 8];
            const y: u8 = V[(opcode & 0x00F0) >> 4];
            const h: u8 = @intCast(opcode & 0x000F);
            var pix: u8 = 0;
            var xline: u3 = 0;
            var drawFlag: bool = false;

            V[0xF] = 0;
            for (0..(h - 1)) |yline| {
                pix = memory[I + yline];
                xline = 0;
                while (xline < 7) : (xline += 1) {
                    const pixBase: u8 = 0x80;
                    if ((pix & (pixBase >> xline)) != 0) {
                        if (gfx[(x + xline + ((y + yline) * 64))] == 1) {
                            V[0xF] = 1;
                        }
                        gfx[x + xline + ((y + yline) * 64)] ^= 1;
                    }
                }
            }
            drawFlag = true;
            pc += 2;
        },
        0xE000 => {
            switch (opcode & 0x00FF) {
                0x009E => {
                    if (keys[(opcode & 0x0F00) >> 8] == 1) {
                        pc += 2;
                    }
                },
                0x00A1 => {
                    if (keys[(opcode & 0x0F00) >> 8] != 1) {
                        pc += 2;
                    }
                },
                else => {
                    @panic("Invalid opcode [0xE000]: {}\n");
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
                    const v: u8 = @intCast((opcode & 0x0F00) >> 8);
                    while (i <= v) {
                        V[i] = memory[I + v];
                        i += 1;
                    }
                    pc += 2;
                },
                else => {
                    @panic("Invalid opcode [0xF000]: {}\n");
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
                    for (&gfx) |*px| {
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

    if (delay_timer > 0) {
        delay_timer = delay_timer - 1;
    }
    if (sound_timer > 0) {
        //std.fs.File.writer(std.io.getStdOut()).writeAll("BEEEP!\n");
        sound_timer = sound_timer - 1;
    }
}

pub fn keypress(k: u8) void {
    keys[k] = 1;
}

pub fn keyrelease(k: u8) void {
    keys[k] = 0;
}

pub fn load(path: []const u8) !void {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(path, .{ .mode = .read_only });
    defer file.close();

    var buf: [3896]u8 = undefined;
    const len = try file.readAll(buf[0..]);

    for (0..len) |i| {
        memory[200 + i] = buf[i];
    }
}

const fontset = [80]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

fn range(len: usize) []const void {
    return @as([*]void, undefined)[0..len];
}
