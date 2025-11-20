const std = @import("std");
const zig8 = @import("zig8");
//const beeper = @import("beep");
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
const base_display_w: u64 = 1024;
const base_display_h: u64 = 512;
var display_w: u64 = base_display_w;
var display_h: u64 = base_display_h;
var display_size_pct: f64 = 1.0;
const min_display_size_pct: f64 = 0.5;
const max_display_size_pct: f64 = 4.0;
var update_window_size: bool = false; // update window when display size changed
var toggle_shader: bool = true; // true = use shader

// Simulating CPU hz
var last_update_time: f64 = 0.0;
var cycle_delay: f64 = 4.0; // ms to accumulate between CPU cycles

// OpenGL Vars
var program_id: gl.GLuint = undefined;
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

const palette_light = [_]u32{
    rgba(255, 255, 255, 255),
    rgba(255, 166, 7, 255),
    rgba(15, 56, 15, 255),
};

const palette_dark = [_]u32{
    rgba(0, 0, 0, 0),
    rgba(8, 8, 8, 255),
    rgba(139, 172, 15, 255),
};

var selected_palette: usize = 0;

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var args = std.process.args();
    defer args.deinit();

    _ = args.skip();
    const rom_path = args.next() orelse "";

    const seed: u64 = @intCast(std.time.timestamp());
    const prng = std.Random.DefaultPrng.init(seed);

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_AUDIO) != 0) {
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
        if (!init_gl_extensions()) {
            std.debug.print("Could not initialize extensions!\n", .{});
        }

        program_id = try compile_program();
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

    var audio_spec: sdl.SDL_AudioSpec = .{};
    audio_spec.freq = 44100;
    audio_spec.format = sdl.AUDIO_S32LSB;
    audio_spec.samples = 1024;

    const audio_device = sdl.SDL_OpenAudioDevice(null, 0, &audio_spec, null, sdl.SDL_AUDIO_ALLOW_ANY_CHANGE);
    defer sdl.SDL_CloseAudioDevice(audio_device);

    sdl.SDL_PauseAudioDevice(audio_device, 0);

    const audio_spawn_cfg = std.Thread.SpawnConfig{
        .allocator = alloc,
    };

    zig8.initialize(prng);
    try zig8.load(rom_path);

    var running = true;

    const audio_thread = try std.Thread.spawn(audio_spawn_cfg, do_audio, .{ audio_spec, audio_device, &running });
    defer audio_thread.join();

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
                        sdl.SDLK_BACKQUOTE => {
                            selected_palette = @mod(selected_palette + 1, palette_light.len);
                        },
                        sdl.SDLK_BACKSLASH => {
                            toggle_shader ^= true;
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

        render(screen, renderer, screen_texture);
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

fn render(win: *sdl.SDL_Window, renderer: *sdl.SDL_Renderer, texture: *sdl.SDL_Texture) void {
    _ = sdl.SDL_RenderClear(renderer);
    var pixels: [2048]u32 = undefined;
    for (0..screen_w) |x| {
        for (0..screen_h) |y| {
            const pixel_active = zig8.gfx[(screen_w * y) + x] == 1;
            if (pixel_active) {
                pixels[(screen_w * y) + x] = palette_light[selected_palette];
            } else {
                pixels[(screen_w * y) + x] = palette_dark[selected_palette];
            }
        }
    }
    _ = sdl.SDL_UpdateTexture(texture, null, &pixels, screen_w * 4);
    render_present(win, renderer, texture);
    const display_rect: sdl.SDL_Rect = .{ .x = 0, .y = 0, .w = @as(c_int, @intCast(display_w)), .h = @as(c_int, @intCast(display_h)) };
    _ = sdl.SDL_RenderCopy(renderer, texture, null, &display_rect);
}

fn render_present(win: *sdl.SDL_Window, renderer: *sdl.SDL_Renderer, back_buffer: *sdl.SDL_Texture) void {
    var old_program_id: gl.GLint = undefined;

    _ = sdl.SDL_SetRenderTarget(renderer, null);
    _ = sdl.SDL_RenderClear(renderer);
    _ = sdl.SDL_GL_BindTexture(back_buffer, null, null);

    if (program_id != 0 and toggle_shader) {
        gl.glGetIntegerv(gl.GL_CURRENT_PROGRAM, &old_program_id);
        glUseProgram.?(program_id);
    }

    const minx: gl.GLfloat = 0.0;
    const miny: gl.GLfloat = 0.0;
    const maxx: gl.GLfloat = @floatFromInt(display_w);
    const maxy: gl.GLfloat = @floatFromInt(display_h);
    const minu: gl.GLfloat = 0.0;
    const maxu: gl.GLfloat = 1.0;
    const minv: gl.GLfloat = 0.0;
    const maxv: gl.GLfloat = 1.0;

    gl.glBegin(gl.GL_TRIANGLE_STRIP);
    gl.glTexCoord2f(minu, minv);
    gl.glVertex2f(minx, miny);
    gl.glTexCoord2f(maxu, minv);
    gl.glVertex2f(maxx, miny);
    gl.glTexCoord2f(minu, maxv);
    gl.glVertex2f(minx, maxy);
    gl.glTexCoord2f(maxu, maxv);
    gl.glVertex2f(maxx, maxy);
    gl.glEnd();

    sdl.SDL_GL_SwapWindow(win);

    if (program_id != 0 and toggle_shader) {
        glUseProgram.?(@intCast(old_program_id));
    }
}

fn do_audio(audio_spec: sdl.SDL_AudioSpec, audio_device: sdl.SDL_AudioDeviceID, running: *bool) !void {
    while (running.*) {
        if (zig8.should_beep()) {
            sdl.SDL_PauseAudioDevice(audio_device, 0);
            const alloc = std.heap.page_allocator;
            var buf = try alloc.alloc(f64, @as(usize, @as(usize, @intCast(audio_spec.freq)) * @as(usize, 3)));
            defer alloc.free(buf);

            var samp: f64 = 0.0;
            for (0..@as(usize, @intCast(audio_spec.freq)) * @as(usize, 3)) |i| {
                buf[i] = std.math.sin(samp * 2.0) * 5000.0;
                samp += 0.010;
            }

            _ = sdl.SDL_QueueAudio(audio_device, @ptrCast(buf.ptr), @as(u32, @intCast(buf.len)));
        } else {
            sdl.SDL_ClearQueuedAudio(audio_device);
        }
        sdl.SDL_PauseAudioDevice(audio_device, 1);
    }
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
    return (@as(u32, a) << 24) | (@as(u32, b) << 16) | (@as(u32, g) << 8) | @as(u32, r);
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

fn compile_program() !gl.GLuint {
    const alloc = std.heap.page_allocator;
    var prg_id: gl.GLuint = 0;
    var vtx_shader_id: gl.GLuint = undefined;
    var frg_shader_id: gl.GLuint = undefined;

    prg_id = glCreateProgram.?();

    vtx_shader_id = try compile_shader(vtx_source, gl.GL_VERTEX_SHADER);
    frg_shader_id = try compile_shader(frg_source, gl.GL_FRAGMENT_SHADER);

    glAttachShader.?(prg_id, vtx_shader_id);
    glAttachShader.?(prg_id, frg_shader_id);
    glLinkProgram.?(prg_id);
    glValidateProgram.?(prg_id);

    var log_length: gl.GLint = undefined;
    glGetProgramiv.?(prg_id, gl.GL_INFO_LOG_LENGTH, &log_length);

    if (log_length > 0) {
        const log: []u8 = try alloc.alloc(u8, @as(usize, @intCast(log_length)));
        defer alloc.free(log);

        glGetProgramInfoLog.?(prg_id, log_length, &log_length, @ptrCast(log));
        std.debug.print("GL Prog Info Log:\n{s}", .{log});
    }

    glDeleteShader.?(vtx_shader_id);
    glDeleteShader.?(frg_shader_id);

    return prg_id;
}

fn compile_shader(source: []const u8, shader_type: gl.GLuint) !gl.GLuint {
    const alloc = std.heap.page_allocator;
    const result: gl.GLuint = glCreateShader.?(shader_type);
    glShaderSource.?(result, 1, @ptrCast(&source), null);
    glCompileShader.?(result);

    // check for compilation errors
    var shader_compiled: gl.GLint = gl.GL_FALSE;
    _ = glGetShaderiv.?(result, gl.GL_COMPILE_STATUS, &shader_compiled);
    if (shader_compiled != gl.GL_TRUE) {
        std.debug.print("Error compiling shader: {d}\n", .{result});
        var log_length: gl.GLint = undefined;
        glGetShaderiv.?(result, gl.GL_INFO_LOG_LENGTH, &log_length);

        if (log_length > 0) {
            const log: []u8 = try alloc.alloc(u8, @as(usize, @intCast(log_length)));
            defer alloc.free(log);

            glGetShaderInfoLog.?(result, log_length, &log_length, @ptrCast(log));
            std.debug.print("Compile log: {s}\n", .{log});
        }
    } else {
        std.debug.print("Shader compiled correctly!\n", .{});
    }

    return result;
}

const vtx_source =
    \\ varying vec4 v_color;
    \\ varying vec2 v_texCoord;
    \\
    \\ void main()
    \\     {
    \\         gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
    \\         v_color = gl_Color;
    \\         v_texCoord = vec2(gl_MultiTexCoord0);
    \\ }
;

const frg_source =
    \\ //
    \\ // PUBLIC DOMAIN CRT STYLED SCAN-LINE SHADER
    \\ //
    \\ //   by Timothy Lottes
    \\ //
    \\ // This is more along the style of a really good CGA arcade monitor.
    \\ // With RGB inputs instead of NTSC.
    \\ // The shadow mask example has the mask rotated 90 degrees for less chromatic aberration.
    \\ //
    \\ // Left it unoptimized to show the theory behind the algorithm.
    \\ //
    \\ // It is an example what I personally would want as a display option for pixel art games.
    \\ // Please take and use, change, or whatever.
    \\ //
    \\
    \\ varying vec4 v_color;
    \\ varying vec2 v_texCoord;
    \\
    \\ uniform sampler2D tex0;
    \\
    \\ // Hardness of scanline.
    \\ //  -8.0 = soft
    \\ // -16.0 = medium
    \\ float hardScan=-8.0;
    \\
    \\ // Hardness of pixels in scanline.
    \\ // -2.0 = soft
    \\ // -4.0 = hard
    \\ float hardPix=-2.0;
    \\
    \\ // Display warp.
    \\ // 0.0 = none
    \\ // 1.0/8.0 = extreme
    \\ vec2 warp=vec2(1.0/32.0,1.0/24.0);
    \\
    \\ // Amount of shadow mask.
    \\ float maskDark=1.0;
    \\ float maskLight=1.5;
    \\
    \\ vec2 res = vec2(640.0,480.0); // /3.0
    \\
    \\ //------------------------------------------------------------------------
    \\
    \\ // sRGB to Linear.
    \\ // Assuing using sRGB typed textures this should not be needed.
    \\ float ToLinear1(float c){return(c<=0.04045)?c/12.92:pow((c+0.055)/1.055,2.4);}
    \\ vec3 ToLinear(vec3 c){return vec3(ToLinear1(c.r),ToLinear1(c.g),ToLinear1(c.b));}
    \\
    \\ // Linear to sRGB.
    \\ // Assuing using sRGB typed textures this should not be needed.
    \\ float ToSrgb1(float c){return(c<0.0031308?c*12.92:1.055*pow(c,0.41666)-0.055);}
    \\ vec3 ToSrgb(vec3 c){return vec3(ToSrgb1(c.r),ToSrgb1(c.g),ToSrgb1(c.b));}
    \\
    \\ // Nearest emulated sample given floating point position and texel offset.
    \\ // Also zero's off screen.
    \\ vec3 Fetch(vec2 pos,vec2 off){
    \\   pos=floor(pos*res+off)/res;
    \\   if(max(abs(pos.x-0.5),abs(pos.y-0.5))>0.5)return vec3(0.0,0.0,0.0);
    \\   return ToLinear(texture2D(tex0,pos.xy,-16.0).rgb);}
    \\
    \\ // Distance in emulated pixels to nearest texel.
    \\ vec2 Dist(vec2 pos){pos=pos*res;return -((pos-floor(pos))-vec2(0.5));}
    \\
    \\ // 1D Gaussian.
    \\ float Gaus(float pos,float scale){return exp2(scale*pos*pos);}
    \\
    \\ // 3-tap Gaussian filter along horz line.
    \\ vec3 Horz3(vec2 pos,float off){
    \\   vec3 b=Fetch(pos,vec2(-1.0,off));
    \\   vec3 c=Fetch(pos,vec2( 0.0,off));
    \\   vec3 d=Fetch(pos,vec2( 1.0,off));
    \\   float dst=Dist(pos).x;
    \\   // Convert distance to weight.
    \\   float scale=hardPix;
    \\   float wb=Gaus(dst-1.0,scale);
    \\   float wc=Gaus(dst+0.0,scale);
    \\   float wd=Gaus(dst+1.0,scale);
    \\   // Return filtered sample.
    \\   return (b*wb+c*wc+d*wd)/(wb+wc+wd);}
    \\
    \\ // 5-tap Gaussian filter along horz line.
    \\ vec3 Horz5(vec2 pos,float off){
    \\   vec3 a=Fetch(pos,vec2(-2.0,off));
    \\   vec3 b=Fetch(pos,vec2(-1.0,off));
    \\   vec3 c=Fetch(pos,vec2( 0.0,off));
    \\   vec3 d=Fetch(pos,vec2( 1.0,off));
    \\   vec3 e=Fetch(pos,vec2( 2.0,off));
    \\   float dst=Dist(pos).x;
    \\   // Convert distance to weight.
    \\   float scale=hardPix;
    \\   float wa=Gaus(dst-2.0,scale);
    \\   float wb=Gaus(dst-1.0,scale);
    \\   float wc=Gaus(dst+0.0,scale);
    \\   float wd=Gaus(dst+1.0,scale);
    \\   float we=Gaus(dst+2.0,scale);
    \\   // Return filtered sample.
    \\   return (a*wa+b*wb+c*wc+d*wd+e*we)/(wa+wb+wc+wd+we);}
    \\
    \\ // Return scanline weight.
    \\ float Scan(vec2 pos,float off){
    \\   float dst=Dist(pos).y;
    \\   return Gaus(dst+off,hardScan);}
    \\
    \\ // Allow nearest three lines to effect pixel.
    \\ vec3 Tri(vec2 pos){
    \\   vec3 a=Horz3(pos,-1.0);
    \\   vec3 b=Horz5(pos, 0.0);
    \\   vec3 c=Horz3(pos, 1.0);
    \\   float wa=Scan(pos,-1.0);
    \\   float wb=Scan(pos, 0.0);
    \\   float wc=Scan(pos, 1.0);
    \\   return a*wa+b*wb+c*wc;}
    \\
    \\ // Distortion of scanlines, and end of screen alpha.
    \\ vec2 Warp(vec2 pos){
    \\   pos=pos*2.0-1.0;
    \\   pos*=vec2(1.0+(pos.y*pos.y)*warp.x,1.0+(pos.x*pos.x)*warp.y);
    \\   return pos*0.5+0.5;}
    \\
    \\ // Shadow mask.
    \\ vec3 Mask(vec2 pos){
    \\   pos.x+=pos.y*3.0;
    \\   vec3 mask=vec3(maskDark,maskDark,maskDark);
    \\   pos.x=fract(pos.x/6.0);
    \\   if(pos.x<0.333)mask.r=maskLight;
    \\   else if(pos.x<0.666)mask.g=maskLight;
    \\   else mask.b=maskLight;
    \\   return mask;}
    \\
    \\ // Draw dividing bars.
    \\ float Bar(float pos,float bar){pos-=bar;return pos*pos<4.0?0.0:1.0;}
    \\
    \\ // Entry.
    \\ void main(){
    \\   // Unmodified.
    \\   vec2 pos=Warp(v_texCoord);
    \\   vec4 fragColor;
    \\   fragColor.rgb=Tri(pos)*Mask(gl_FragCoord.xy);
    \\   fragColor.rgb=ToSrgb(fragColor.rgb);
    \\   gl_FragColor=v_color * vec4(fragColor.rgb, 1.0);
    \\ }
;
