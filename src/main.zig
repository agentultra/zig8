const std = @import("std");
const zig8 = @import("zig8");
const c = @cImport({
    @cInclude("string.h");
});
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL_opengl.h");
    @cInclude("SDL_opengl_glext.h");
});
const gl = @cImport({
    @cInclude("GL/gl.h");
});

// The emulated screen dimensions
const screen_w = 64;
const screen_h = 32;

// The display dimensions in pixel units
const base_display_w: u64 = 256;
const base_display_h: u64 = 128;
var display_w: u64 = base_display_w;
var display_h: u64 = base_display_h;
var display_size_pct: f64 = 1.0;
const min_display_size_pct: f64 = 0.5;
const max_display_size_pct: f64 = 3.0;
var update_window_size: bool = false; // update window when display size changed

// Simulating CPU hz
var last_update_time: f64 = 0.0;
var cycle_delay: f64 = 4.0; // ms to accumulate between CPU cycles

// OpenGL Vars
var programId: gl.GLuint = undefined;
var glCreateShader: gl.PFNGLCREATESHADERPROC = undefined;
var glShaderSource: gl.PFNGLSHADERSOURCEPROC = undefined;
var glCompileShader: gl.PFNGLCOMPILESHADERPROC = undefined;
var glGetShaderiv: gl.PFNGLGETSHADERIVPROC = undefined;
var glGetShaderInfoLog: gl.PFNGLGETSHADERINFOLOGPROC = undefined;
var glDeleteShader: gl.PFNGLDELETESHADERPROC = undefined;
var glAttachShader: gl.PFNGLATTACHSHADERPROC = undefined;
var glCreateProgram: gl.PFNGLCREATEPROGRAMPROC = undefined;
var glLinkProgram: gl.PFNGLLINKPROGRAMPROC = undefined;
var glValidateProgram: gl.PFNGLVALIDATEPROGRAMPROC = undefined;
var glGetProgramiv: gl.PFNGLGETPROGRAMIVPROC = undefined;
var glGetProgramInfoLog: gl.PFNGLGETPROGRAMINFOLOGPROC = undefined;
var glUseProgram: gl.PFNGLUSEPROGRAMPROC = undefined;

pub fn main() !void {
    var args = std.process.args();
    defer args.deinit();

    _ = args.skip();
    const rom_path = args.next() orelse "";

    const seed: u64 = @intCast(std.time.timestamp());
    const prng = std.Random.DefaultPrng.init(seed);

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        sdl.SDL_Log("Unable to initialize SDL: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer sdl.SDL_Quit();

    const screen = sdl.SDL_CreateWindow("zig8", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, @as(c_int, @intCast(display_w)), @as(c_int, @intCast(display_h)), sdl.SDL_WINDOW_OPENGL) orelse
        {
            sdl.SDL_Log("Unable to create window: %s", sdl.SDL_GetError());
            return error.SDLInitializationFailed;
        };
    defer sdl.SDL_DestroyWindow(screen);

    _ = sdl.SDL_SetHint(sdl.SDL_HINT_RENDER_DRIVER, "opengl");

    const renderer = sdl.SDL_CreateRenderer(screen, -1, sdl.SDL_RENDERER_ACCELERATED | sdl.SDL_RENDERER_TARGETTEXTURE) orelse {
        sdl.SDL_Log("Unable to create renderer: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer sdl.SDL_DestroyRenderer(renderer);

    var renderer_info: sdl.SDL_RendererInfo = undefined;
    _ = sdl.SDL_GetRendererInfo(renderer, &renderer_info);

    if (c.strncmp(renderer_info.name, "opengl", 6) != 1) {
        std.debug.print("It's OpenGL!\n", .{});
        const gl_extensions_initialized = init_gl_extensions();
        if (!gl_extensions_initialized) {
            std.debug.print("Could not initialize extensions!\n", .{});
        }
    }

    const screen_texture = sdl.SDL_CreateTexture(
        renderer,
        sdl.SDL_PIXELFORMAT_RGBA32,
        sdl.SDL_TEXTUREACCESS_TARGET,
        screen_w,
        screen_h,
    ) orelse {
        sdl.SDL_Log("Unable to create screen texture: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer sdl.SDL_DestroyTexture(screen_texture);

    zig8.initialize(prng);
    try zig8.load(rom_path);

    var running = true;

    last_update_time = get_current_ms();

    while (running) {
        const current_time = get_current_ms();
        const dt = current_time - last_update_time;

        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    running = false;
                },
                sdl.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        sdl.SDLK_ESCAPE => {
                            running = false;
                        },
                        sdl.SDLK_LEFTBRACKET => {
                            cycle_delay = if (cycle_delay < 10.0) cycle_delay + 1.0 else 0.0;
                        },
                        sdl.SDLK_RIGHTBRACKET => {
                            cycle_delay = if (cycle_delay > 0.0) cycle_delay - 1.0 else 0.0;
                        },
                        sdl.SDLK_COMMA => {
                            display_size_pct = @max(min_display_size_pct, display_size_pct - 0.1);
                            update_window_size = true;
                        },
                        sdl.SDLK_PERIOD => {
                            display_size_pct = @min(max_display_size_pct, display_size_pct + 0.1);
                            update_window_size = true;
                        },
                        else => {
                            updatekeypresses(event.key);
                        },
                    }
                },
                sdl.SDL_KEYUP => {
                    updatekeypresses(event.key);
                },
                else => {},
            }
        }

        display_w = @intFromFloat(@as(f64, @floatFromInt(base_display_w)) * display_size_pct);
        display_h = @intFromFloat(@as(f64, @floatFromInt(base_display_h)) * display_size_pct);
        if (update_window_size) {
            sdl.SDL_SetWindowSize(screen, @as(c_int, @intCast(display_w)), @as(c_int, @intCast(display_h)));
            update_window_size = false;
        }

        if (dt > cycle_delay) {
            last_update_time = current_time;
            zig8.cycle();
        }
        render(renderer, screen_texture);
    }
}

fn updatekeypresses(kevt: sdl.SDL_KeyboardEvent) void {
    switch (kevt.type) {
        sdl.SDL_KEYDOWN => {
            switch (kevt.keysym.sym) {
                sdl.SDLK_1 => {
                    zig8.keypress(1);
                },
                sdl.SDLK_2 => {
                    zig8.keypress(2);
                },
                sdl.SDLK_3 => {
                    zig8.keypress(3);
                },
                sdl.SDLK_4 => {
                    zig8.keypress(12);
                },
                sdl.SDLK_q => {
                    zig8.keypress(4);
                },
                sdl.SDLK_w => {
                    zig8.keypress(5);
                },
                sdl.SDLK_e => {
                    zig8.keypress(6);
                },
                sdl.SDLK_r => {
                    zig8.keypress(13);
                },
                sdl.SDLK_a => {
                    zig8.keypress(7);
                },
                sdl.SDLK_s => {
                    zig8.keypress(8);
                },
                sdl.SDLK_d => {
                    zig8.keypress(9);
                },
                sdl.SDLK_f => {
                    zig8.keypress(14);
                },
                sdl.SDLK_z => {
                    zig8.keypress(10);
                },
                sdl.SDLK_x => {
                    zig8.keypress(0);
                },
                sdl.SDLK_c => {
                    zig8.keypress(11);
                },
                sdl.SDLK_v => {
                    zig8.keypress(15);
                },
                else => {},
            }
        },
        sdl.SDL_KEYUP => {
            switch (kevt.keysym.sym) {
                sdl.SDLK_1 => {
                    zig8.keyrelease(1);
                },
                sdl.SDLK_2 => {
                    zig8.keyrelease(2);
                },
                sdl.SDLK_3 => {
                    zig8.keyrelease(3);
                },
                sdl.SDLK_4 => {
                    zig8.keyrelease(12);
                },
                sdl.SDLK_q => {
                    zig8.keyrelease(4);
                },
                sdl.SDLK_w => {
                    zig8.keyrelease(5);
                },
                sdl.SDLK_e => {
                    zig8.keyrelease(6);
                },
                sdl.SDLK_r => {
                    zig8.keyrelease(13);
                },
                sdl.SDLK_a => {
                    zig8.keyrelease(7);
                },
                sdl.SDLK_s => {
                    zig8.keyrelease(8);
                },
                sdl.SDLK_d => {
                    zig8.keyrelease(9);
                },
                sdl.SDLK_f => {
                    zig8.keyrelease(14);
                },
                sdl.SDLK_z => {
                    zig8.keyrelease(10);
                },
                sdl.SDLK_x => {
                    zig8.keyrelease(0);
                },
                sdl.SDLK_c => {
                    zig8.keyrelease(11);
                },
                sdl.SDLK_v => {
                    zig8.keyrelease(15);
                },
                else => {},
            }
        },
        else => {},
    }
}

fn render(renderer: *sdl.SDL_Renderer, texture: *sdl.SDL_Texture) void {
    _ = sdl.SDL_RenderClear(renderer);
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
    _ = sdl.SDL_UpdateTexture(texture, null, &pixels, screen_w * 4);
    const display_rect: sdl.SDL_Rect = .{ .x = 0, .y = 0, .w = @as(c_int, @intCast(display_w)), .h = @as(c_int, @intCast(display_h)) };
    _ = sdl.SDL_RenderCopy(renderer, texture, null, &display_rect);
    sdl.SDL_RenderPresent(renderer);
}

fn get_current_ms() f64 {
    return (get_performance_counter() / get_performance_frequency()) * 1000;
}

fn get_performance_counter() f64 {
    return @as(f64, @floatFromInt(sdl.SDL_GetPerformanceCounter()));
}

fn get_performance_frequency() f64 {
    return @as(f64, @floatFromInt(sdl.SDL_GetPerformanceFrequency()));
}

fn rgba(r: u8, g: u8, b: u8, a: u8) u32 {
    return (@as(u32, r) << 24) | (@as(u32, g) << 16) | (@as(u32, b) << 8) | @as(u32, a);
}

// OpenGL Helpers
fn init_gl_extensions() bool {
    glCreateShader = @ptrCast(sdl.SDL_GL_GetProcAddress("glCreateShader"));
    glShaderSource = @ptrCast(sdl.SDL_GL_GetProcAddress("glShaderSource"));
    glCompileShader = @ptrCast(sdl.SDL_GL_GetProcAddress("glCompileShader"));
    glGetShaderiv = @ptrCast(sdl.SDL_GL_GetProcAddress("glGetShaderiv"));
    glGetShaderInfoLog = @ptrCast(sdl.SDL_GL_GetProcAddress("glGetShaderInfoLog"));
    glDeleteShader = @ptrCast(sdl.SDL_GL_GetProcAddress("glDeleteShader"));
    glAttachShader = @ptrCast(sdl.SDL_GL_GetProcAddress("glAttachShader"));
    glCreateProgram = @ptrCast(sdl.SDL_GL_GetProcAddress("glCreateProgram"));
    glLinkProgram = @ptrCast(sdl.SDL_GL_GetProcAddress("glLinkProgram"));
    glValidateProgram = @ptrCast(sdl.SDL_GL_GetProcAddress("glValidateProgram"));
    glGetProgramiv = @ptrCast(sdl.SDL_GL_GetProcAddress("glGetProgramiv"));
    glGetProgramInfoLog = @ptrCast(sdl.SDL_GL_GetProcAddress("glGetProgramInfoLog"));
    glUseProgram = @ptrCast(sdl.SDL_GL_GetProcAddress("glUseProgram"));
    return glCreateShader != null and
        glShaderSource != null and
        glCompileShader != null and
        glGetShaderiv != null and
        glGetShaderInfoLog != null and
        glDeleteShader != null and
        glAttachShader != null and
        glCreateProgram != null and
        glLinkProgram != null and
        glValidateProgram != null and
        glGetProgramiv != null and
        glGetProgramInfoLog != null and
        glUseProgram != null;
}
