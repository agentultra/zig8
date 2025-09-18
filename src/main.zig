const std = @import("std");
const zig8 = @import("zig8");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const screen_w = 64;
const screen_h = 32;

pub fn main() !void {
    var args = std.process.args();
    defer args.deinit();

    _ = args.skip();
    const rom_path = args.next() orelse "";

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const screen = c.SDL_CreateWindow("zig8", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 400, 140, c.SDL_WINDOW_OPENGL) orelse
        {
            c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
    defer c.SDL_DestroyWindow(screen);

    const renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    zig8.initialize();
    try zig8.load(rom_path);

    var running = true;

    while (running) {
        zig8.cycle();
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    running = false;
                },
                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_ESCAPE => {
                            running = false;
                        },
                        else => {
                            updatekeypresses(event.key);
                        },
                    }
                },
                c.SDL_KEYUP => {
                    updatekeypresses(event.key);
                },
                else => {},
            }
        }
        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
        for (0..screen_w) |x| {
            for (0..screen_h) |y| {
                //std.debug.print("x {d}, y {d}\n", .{ x, y });
                const pixel_active = zig8.gfx[(screen_w * y) + x] == 1;
                if (pixel_active) {
                    const p: c.SDL_Rect = .{ .x = @as(c_int, @intCast(x * 4)), .y = @as(c_int, @intCast(y * 4)), .w = 4, .h = 4 };
                    _ = c.SDL_RenderFillRect(renderer, &p);
                }
            }
        }
        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0);
        c.SDL_RenderPresent(renderer);
        c.SDL_Delay(3);
    }
}

fn updatekeypresses(kevt: c.SDL_KeyboardEvent) void {
    switch (kevt.type) {
        c.SDL_KEYDOWN => {
            switch (kevt.keysym.sym) {
                c.SDLK_1 => {
                    zig8.keypress(1);
                },
                c.SDLK_2 => {
                    zig8.keypress(2);
                },
                c.SDLK_3 => {
                    zig8.keypress(3);
                },
                c.SDLK_4 => {
                    zig8.keypress(12);
                },
                c.SDLK_q => {
                    zig8.keypress(4);
                },
                c.SDLK_w => {
                    zig8.keypress(5);
                },
                c.SDLK_e => {
                    zig8.keypress(6);
                },
                c.SDLK_r => {
                    zig8.keypress(13);
                },
                c.SDLK_a => {
                    zig8.keypress(7);
                },
                c.SDLK_s => {
                    zig8.keypress(8);
                },
                c.SDLK_d => {
                    zig8.keypress(9);
                },
                c.SDLK_f => {
                    zig8.keypress(14);
                },
                c.SDLK_z => {
                    zig8.keypress(10);
                },
                c.SDLK_x => {
                    zig8.keypress(0);
                },
                c.SDLK_c => {
                    zig8.keypress(11);
                },
                c.SDLK_v => {
                    zig8.keypress(15);
                },
                else => {},
            }
        },
        c.SDL_KEYUP => {
            switch (kevt.keysym.sym) {
                c.SDLK_1 => {
                    zig8.keyrelease(1);
                },
                c.SDLK_2 => {
                    zig8.keyrelease(2);
                },
                c.SDLK_3 => {
                    zig8.keyrelease(3);
                },
                c.SDLK_4 => {
                    zig8.keyrelease(12);
                },
                c.SDLK_q => {
                    zig8.keyrelease(4);
                },
                c.SDLK_w => {
                    zig8.keyrelease(5);
                },
                c.SDLK_e => {
                    zig8.keyrelease(6);
                },
                c.SDLK_r => {
                    zig8.keyrelease(13);
                },
                c.SDLK_a => {
                    zig8.keyrelease(7);
                },
                c.SDLK_s => {
                    zig8.keyrelease(8);
                },
                c.SDLK_d => {
                    zig8.keyrelease(9);
                },
                c.SDLK_f => {
                    zig8.keyrelease(14);
                },
                c.SDLK_z => {
                    zig8.keyrelease(10);
                },
                c.SDLK_x => {
                    zig8.keyrelease(0);
                },
                c.SDLK_c => {
                    zig8.keyrelease(11);
                },
                c.SDLK_v => {
                    zig8.keyrelease(15);
                },
                else => {},
            }
        },
        else => {},
    }
}
