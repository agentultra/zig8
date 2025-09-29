const std = @import("std");
const zig8 = @import("zig8");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

// The emulated screen dimensions
const screen_w = 64;
const screen_h = 32;

// The display dimensions
var display_w: u64 = 64 * 4;
var display_h: u64 = 32 * 4;

// Resize debouncing
const resize_delay: f64 = 10.0;
var resize_pending: bool = true;

// Simulating CPU hz
var last_update_time: f64 = 0.0;
var cycle_delay: f64 = 4.0; // ms to accumulate between CPU cycles

pub fn main() !void {
    var args = std.process.args();
    defer args.deinit();

    _ = args.skip();
    const rom_path = args.next() orelse "";

    const seed: u64 = @intCast(std.time.timestamp());
    const prng = std.Random.DefaultPrng.init(seed);

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const screen = c.SDL_CreateWindow("zig8", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 400, 140, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE) orelse
        {
            c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
    defer c.SDL_DestroyWindow(screen);

    c.SDL_AddEventWatch(resizing_event_watcher, screen);

    const renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    const screen_texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_TARGET,
        screen_w,
        screen_h,
    ) orelse {
        c.SDL_Log("Unable to create screen texture: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyTexture(screen_texture);

    zig8.initialize(prng);
    try zig8.load(rom_path);

    var running = true;

    last_update_time = get_current_ms();

    while (running) {
        const current_time = get_current_ms();
        const dt = current_time - last_update_time;

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
                        c.SDLK_LEFTBRACKET => {
                            cycle_delay = if (cycle_delay < 10.0) cycle_delay + 1.0 else 0.0;
                        },
                        c.SDLK_RIGHTBRACKET => {
                            cycle_delay = if (cycle_delay > 0.0) cycle_delay - 1.0 else 0.0;
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

        if (dt > resize_delay) {
            resize_pending = true;
        }

        if (dt > cycle_delay) {
            last_update_time = current_time;
            zig8.cycle();
        }
        render(renderer, screen_texture);
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

fn render(renderer: *c.SDL_Renderer, texture: *c.SDL_Texture) void {
    _ = c.SDL_RenderClear(renderer);
    var pixels: [2048]u32 = undefined;
    for (0..screen_w) |x| {
        for (0..screen_h) |y| {
            const pixel_active = zig8.gfx[(screen_w * y) + x] == 1;
            if (pixel_active) {
                pixels[(screen_w * y) + x] = rgba(255, 255, 255, 255);
            } else {
                pixels[(screen_w * y) + x] = rgba(0, 0, 0, 0);
            }
        }
    }
    _ = c.SDL_UpdateTexture(texture, null, &pixels, screen_w * 4);
    const display_rect: c.SDL_Rect = .{ .x = 0, .y = 0, .w = @as(c_int, @intCast(display_w)), .h = @as(c_int, @intCast(display_h)) };
    _ = c.SDL_RenderCopy(renderer, texture, null, &display_rect);
    c.SDL_RenderPresent(renderer);
}

fn resizing_event_watcher(data: ?*anyopaque, event: [*c]c.SDL_Event) callconv(.c) c_int {
    if (resize_pending and (event.*.type == c.SDL_WINDOWEVENT) and (event.*.window.event == c.SDL_WINDOWEVENT_RESIZED)) {
        const win: ?*c.SDL_Window = c.SDL_GetWindowFromID(event.*.window.windowID);
        const event_window: *c.SDL_Window = @ptrCast(data);
        if (win == event_window) {
            var win_w: c_int = undefined;
            var win_h: c_int = undefined;
            c.SDL_GetWindowSize(win, &win_w, &win_h);

            std.debug.print("resized w: {d} h: {d}\n", .{ win_w, win_h });
        }

        resize_pending = false;
    }
    return 0;
}

fn get_current_ms() f64 {
    return (get_performance_counter() / get_performance_frequency()) * 1000;
}

fn get_performance_counter() f64 {
    return @as(f64, @floatFromInt(c.SDL_GetPerformanceCounter()));
}

fn get_performance_frequency() f64 {
    return @as(f64, @floatFromInt(c.SDL_GetPerformanceFrequency()));
}

fn rgba(r: u8, g: u8, b: u8, a: u8) u32 {
    return (@as(u32, r) << 24) | (@as(u32, g) << 16) | (@as(u32, b) << 8) | @as(u32, a);
}
