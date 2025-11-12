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
// 0x200-0xFFF - Program ROM and work RAM

var opcode: u16 = undefined;
var memory: [4096]u8 = undefined; // main memory
var V: [16]u8 = undefined; // registers V1 - VE
var I: u16 = undefined; // index register
var ST: u8 = undefined; // sound active register
var pc: u16 = undefined; // program counter
var stack: [16]u16 = undefined; // program stack
var sp: u16 = undefined; // stack pointer
pub var draw_flag: bool = undefined; // when true after one cycle, render
pub var gfx: [2048]u8 = undefined; // graphics memory
var keys: [16]u8 = undefined; // keys
var rand: std.Random.DefaultPrng = undefined; // prng random number generator

var delay_timer: u8 = undefined; // count at 60hz down to zero
var sound_timer: u16 = undefined; // count at 60hz down to zero

const pixMask: u8 = 0x80;

// Emulation API
pub fn initialize(prng: std.Random.DefaultPrng) void {
    opcode = 0;
    pc = 0x200;
    for (&memory) |*loc| {
        loc.* = 0;
    }
    for (0..80) |i| {
        memory[i] = fontset[i];
    }
    for (&V) |*reg| {
        reg.* = 0;
    }
    I = 0;
    ST = 0;
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
    rand = prng;
    delay_timer = 0;
    sound_timer = 0;
}

pub fn should_beep() bool {
    return ST != 0;
}

pub fn cycle() void {
    opcode = @as(u16, memory[pc]) << 8 | memory[pc + 1];

    pc += 2;

    switch (opcode & 0xF000) {
        0x0000 => {
            handle_0xxx(opcode);
        },
        0x1000 => { // JP addr
            const nnn: u16 = @intCast(opcode & 0x0FFF);
            pc = nnn;
        },
        0x2000 => { // CALL addr
            const nnn: u16 = @intCast(opcode & 0x0FFF);
            stack[sp] = pc;
            sp += 1;
            pc = nnn;
        },
        0x3000 => { // SE Vx, byte
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const kk: u8 = @intCast(opcode & 0x00FF);
            if (V[x] == kk) {
                pc += 2;
            }
        },
        0x4000 => { // SNE Vx, byte
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const kk: u8 = @intCast(opcode & 0x00FF);
            if (V[x] != kk) {
                pc += 2;
            }
        },
        0x5000 => { // SE Vx, Vy
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const y: u4 = @intCast((opcode & 0x00F0) >> 4);
            if (V[x] == V[y]) {
                pc += 2;
            }
        },
        0x6000 => { // LD Vx, byte
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const kk: u8 = @intCast(opcode & 0x00FF);
            V[x] = kk;
        },
        0x7000 => { // ADD Vx, byte
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const kk: u8 = @intCast(opcode & 0x00FF);

            V[x] = V[x] +% kk;
        },
        0x8000 => {
            handle_8xxx(opcode);
        },
        0xA000 => { // LD I, addr
            const nnn: u12 = @intCast(opcode & 0x0FFF);
            I = nnn;
        },
        0xB000 => { // JP V0, addr
            const nnn: u12 = @intCast(opcode & 0x0FFF);
            pc = V[0] + nnn;
        },
        0x9000 => { // SNE Vx, Vy
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const y: u4 = @intCast((opcode & 0x00F0) >> 4);
            if (V[x] != V[y]) pc += 2;
        },
        0xC000 => { // RND Vx, byte
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const kk: u8 = @intCast((opcode & 0x00FF));

            const rv: u8 = std.Random.uintAtMost(rand.random(), u8, 255);
            V[x] = rv & kk;
        },
        0xD000 => { // DRW Vx, Vy, nibble
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
                        const i: u32 = ((dy + row) * w);
                        const ix: u64 = (i + dx + col) % 2048;
                        if (gfx[ix] == 1) {
                            V[0xF] = 1;
                        }
                        gfx[ix] ^= 1;
                    }
                }
            }
            draw_flag = true;
        },
        0xE000 => {
            handle_Exxx(opcode);
        },
        0xF000 => {
            handle_Fxxx(opcode);
        },
        else => {
            std.debug.print("Unhandled opcode: 0x{X}\n", .{opcode});
        },
    }

    if (delay_timer > 0) {
        delay_timer = delay_timer - 1;
    }
    if (sound_timer > 0) {
        sound_timer = sound_timer - 1;
    }
    if (sound_timer <= 0) ST = 0;
}

fn handle_0xxx(opc: u16) void {
    switch (opc & 0x00FF) {
        0x00E0 => { // CLEAR
            for (&gfx) |*px| {
                px.* = 0;
            }
        },
        0x00EE => { // RET
            sp -= 1;
            pc = stack[sp];
        },
        else => {},
    }
}

fn handle_8xxx(opc: u16) void {
    switch (opc & 0xF00F) {
        0x8000 => { // LD Vx, Vy
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const y: u4 = @intCast((opcode & 0x00F0) >> 4);
            V[x] = V[y];
        },
        0x8001 => { // OR Vx, Vy
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const y: u4 = @intCast((opcode & 0x00F0) >> 4);
            const xy: u8 = V[x] | V[y];
            V[x] = xy;
        },
        0x8002 => { // AND Vx, Vy
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const y: u4 = @intCast((opcode & 0x00F0) >> 4);
            const xy: u8 = V[x] & V[y];
            V[x] = xy;
        },
        0x8003 => { // XOR Vx, Vy
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const y: u4 = @intCast((opcode & 0x00F0) >> 4);
            const xy: u8 = V[x] ^ V[y];
            V[x] = xy;
        },
        0x8004 => { // ADD Vx, Vy
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const y: u4 = @intCast((opcode & 0x00F0) >> 4);
            const xy: u16 = @as(u16, V[x]) + @as(u16, V[y]);

            V[x] = @intCast(xy & 0xFF);

            if (xy > 255) {
                V[0xF] = 1;
            } else {
                V[0xF] = 0;
            }
        },
        0x8005 => { // SUB Vx, Vy
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const y: u4 = @intCast((opcode & 0x00F0) >> 4);
            const vx = V[x];
            const vy = V[y];

            V[x] = vx -% vy;

            if (vx >= vy) {
                V[0xF] = 1;
            } else {
                V[0xF] = 0;
            }
        },
        0x8006 => { // SHR Vx, {, Vy}
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const vx = V[x];

            V[x] = vx >> 1;

            if ((vx & 0x1) == 1) {
                V[0xF] = 1;
            } else {
                V[0xF] = 0;
            }
        },
        0x8007 => { // SUBN Vx, Vy
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const y: u4 = @intCast((opcode & 0x00F0) >> 4);
            const vx = V[x];
            const vy = V[y];

            V[x] = vy -% vx;

            if (vy >= vx) {
                V[0xF] = 1;
            } else {
                V[0xF] = 0;
            }
        },
        0x800E => { // SH Vx {, Vy}
            const x: u4 = @intCast((opcode & 0x0F00) >> 8);
            const vx = V[x];

            V[x] = vx << 1;

            if (((vx & 0x80) >> 7) == 1) {
                V[0xF] = 1;
            } else {
                V[0xF] = 0;
            }
        },
        else => {},
    }
}

fn handle_Exxx(opc: u16) void {
    switch (opc & 0x00FF) {
        0x009E => { // SKP Vx
            const x: u4 = @intCast((opc & 0x0F00) >> 8);
            const k: u8 = V[x];
            if (keys[k] == 1) pc += 2;
        },
        0x00A1 => { // SKNP Vx
            const x: u4 = @intCast((opc & 0x0F00) >> 8);
            const k: u8 = V[x];

            if (keys[k] == 0) pc += 2;
        },
        else => {},
    }
}

fn handle_Fxxx(opc: u16) void {
    switch (opc & 0x00FF) {
        0x000A => { // LD Vx, K
            const x: u4 = @intCast((opc & 0x0F00) >> 8);
            var pressed = false;
            for (0..15) |i| {
                if (keys[i] == 1) {
                    pressed = true;
                    V[x] = @as(u8, @intCast(i));
                    keys[i] = 0;
                    break;
                }
            }
            if (!pressed) pc -= 2;
        },
        0x0007 => { // LD Vx, DT
            const x: u4 = @intCast((opc & 0x0F00) >> 8);
            V[x] = delay_timer;
        },
        0x0015 => { // LD DT, Vx
            const x: u4 = @intCast((opc & 0x0F00) >> 8);
            delay_timer = V[x];
        },
        0x0018 => { // LD ST, Vx
            const x: u4 = @intCast((opc & 0x0F00) >> 8);
            sound_timer = V[x];
            ST = 1;
        },
        0x001E => { // ADD I, Vx
            const x: u4 = @intCast((opc & 0x0F00) >> 8);
            I = I + V[x];
        },
        0x0029 => { // LD F, Vx
            const x: u4 = @intCast((opc & 0x0F00) >> 8);
            I = @intCast(V[x] * 5);
        },
        0x0033 => { // LD B, Vx
            const x: u4 = @intCast((opc & 0x0F00) >> 8);
            var v: u8 = V[x];

            // ones-place
            memory[I + 2] = v % 10;
            v /= 10;

            // tens-place
            memory[I + 1] = v % 10;
            v /= 10;

            // hundreds-place
            memory[I] = v % 10;
        },
        0x0055 => { // LD [I], Vx
            const x: u4 = @intCast((opc & 0x0F00) >> 8);

            var i: u16 = 0;
            while (i <= x) : (i += 1) {
                memory[I + i] = V[i];
            }
        },
        0x0065 => { // LD Vx, [I]
            const x: u4 = @intCast((opc & 0x0F00) >> 8);

            var i: u16 = 0;
            while (i <= x) : (i += 1) {
                V[i] = memory[I + i];
            }
        },
        else => {},
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
