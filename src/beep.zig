const builtin = @import("builtin");
const std = @import("std");
const target = builtin.target.os.tag;

pub const snd_pcm_stream_t = enum(c_int) {
    PLAYBACK = 0,
    CAPTURE,
};

pub const beep = switch (target) {
    .windows => windows_beep,
    .linux => linux_beep,
    else => default_beep,
};

fn windows_beep(_: u32, _: u64) void {
    return;
}

fn linux_beep(freq: u32, ms: u64) !void {
    const c = @cImport({
        @cInclude("asoundlib.h");
    });

    var err: c_int = undefined;
    var handle: ?*c.snd_pcm_t = undefined;
    err = c.snd_pcm_open(&handle, "default", 0, 0);

    if (err != 0) {
        std.debug.print("Could not open sound for playback\n", .{});
        return error.LinuxAlsaInitializationFailed;
    }

    err = c.snd_pcm_set_params(handle, @as(c_int, @intCast(1)), @as(c_uint, 3), 1, 8000, 1, 20000);

    if (err != 0) {
        std.debug.print("Could not set sound parameters for playback\n", .{});
        return error.LinuxAlsaInitializationFailed;
    }

    var buf: [2400]u8 = undefined;

    for (0..ms / 50) |_| {
        _ = c.snd_pcm_prepare(handle);

        for (0..buf.len - 1) |j| {
            buf[j] = if (freq > 0) 255 *% @as(u8, @intCast(j % 255)) else 0;
        }

        const r: c_long = c.snd_pcm_writei(handle, &buf, buf.len);

        if (r < 0) {
            _ = c.snd_pcm_recover(handle, @as(c_int, @intCast(r)), 0);
        }
    }
}

fn default_beep(_: u32, _: u64) void {
    return;
}
