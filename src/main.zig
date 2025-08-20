const std = @import("std");

pub fn main() !void {
    try std.fs.File.writer(std.io.getStdOut()).writeAll("hello, world!\n");
}
