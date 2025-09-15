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
pub var draw_flag: bool = undefined; // when true after one cycle, render
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
    for (0..80) |i| {
        memory[0x50 + i] = fontset[i];
    }
    for (&V) |*reg| {
        reg.* = 0;
    }
    I = 0;
    for (&stack) |*s| {
        s.* = 0;
    }
    sp = 0;
    draw_flag = false;
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

    pc += 2;

    switch (opcode & 0xF000) {
        0x00E0 => { // CLEAR
            for (&gfx) |*px| {
                px.* = 0;
            }
        },
        0x1000 => {
            const nnn: u16 = @intCast(opcode & 0x0FFF);
            pc = nnn;
        },
        0x6000 => {
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const kk: u8 = @intCast(opcode & 0x00FF);
            V[x] = kk;
        },
        0xA000 => {
            const nnn: u12 = @intCast(opcode & 0x0FFF);
            I = nnn;
        },
        0xD000 => {
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const y: u4 = @intCast((opcode & 0x00F0) >> 4);
            const n: u4 = @intCast(opcode & 0x000F);

            const dx = V[x] & 63;
            const dy = V[y] & 31;
            V[0xF] = 0;

            var row: u8 = 0;
            while (row < n) : (row += 1) {
                const pixel: u8 = memory[I + row];
                var col: u4 = 0;
                while (col < 8) : (col += 1) {
                    const base: u16 = 0x80;
                    if ((pixel & (base >> col)) != 0) {
                        const w: u32 = 64;
                        const i: u32 = (dy + row) * w;
                        const ix: u64 = i + dx + col;
                        if (gfx[ix] == 1) {
                            V[0xF] = 1;
                        }
                        gfx[ix] ^= 1;
                    }
                }
            }
            draw_flag = true;
        },
        else => {},
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
        memory[0x200 + i] = buf[i];
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
