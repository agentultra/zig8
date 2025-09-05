const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

extern fn initialize() void;
extern fn cycle() void;
extern fn keypress(u16) void;
extern fn keyrelease(u16) void;

pub fn main() !void {
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

    initialize();

    var running = true;

    while (running) {
        cycle();
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
                else => {},
            }
        }
        _ = c.SDL_RenderClear(renderer);
        c.SDL_RenderPresent(renderer);
        c.SDL_Delay(30);
    }
}

fn updatekeypresses(kevt: c.SDL_KeyboardEvent) void {
    switch (kevt.type) {
        c.SDL_KEYDOWN => {
            switch (kevt.keysym.sym) {
                c.SDLK_1 => {
                    keypress(0);
                },
                c.SDLK_2 => {
                    keypress(1);
                },
                c.SDLK_3 => {
                    keypress(2);
                },
                c.SDLK_4 => {
                    keypress(3);
                },
                c.SDLK_q => {
                    keypress(4);
                },
                c.SDLK_w => {
                    keypress(5);
                },
                c.SDLK_e => {
                    keypress(6);
                },
                c.SDLK_r => {
                    keypress(7);
                },
                c.SDLK_a => {
                    keypress(8);
                },
                c.SDLK_s => {
                    keypress(9);
                },
                c.SDLK_d => {
                    keypress(10);
                },
                c.SDLK_f => {
                    keypress(11);
                },
                c.SDLK_z => {
                    keypress(12);
                },
                c.SDLK_x => {
                    keypress(13);
                },
                c.SDLK_c => {
                    keypress(14);
                },
                c.SDLK_v => {
                    keypress(15);
                },
                else => {},
            }
        },
        c.SDL_KEYUP => {
            switch (kevt.keysym.sym) {
                c.SDLK_1 => {
                    keyrelease(0);
                },
                c.SDLK_2 => {
                    keyrelease(1);
                },
                c.SDLK_3 => {
                    keyrelease(2);
                },
                c.SDLK_4 => {
                    keyrelease(3);
                },
                c.SDLK_q => {
                    keyrelease(4);
                },
                c.SDLK_w => {
                    keyrelease(5);
                },
                c.SDLK_e => {
                    keyrelease(6);
                },
                c.SDLK_r => {
                    keyrelease(7);
                },
                c.SDLK_a => {
                    keyrelease(8);
                },
                c.SDLK_s => {
                    keyrelease(9);
                },
                c.SDLK_d => {
                    keyrelease(10);
                },
                c.SDLK_f => {
                    keyrelease(11);
                },
                c.SDLK_z => {
                    keyrelease(12);
                },
                c.SDLK_x => {
                    keyrelease(13);
                },
                c.SDLK_c => {
                    keyrelease(14);
                },
                c.SDLK_v => {
                    keyrelease(15);
                },
                else => {},
            }
        },
        else => {},
    }
}
