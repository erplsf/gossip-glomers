const std = @import("std");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const stderr_file = std.io.getStdErr().writer();
    var stderr_bw = std.io.bufferedWriter(stderr_file);
    const stderr = stderr_bw.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const stdin_file = std.io.getStdIn().reader();

    while (true) {
        stdin_file.streamUntilDelimiter(buffer.writer(), '\n', null) catch |err| {
            if (err == error.EndOfStream) std.process.exit(0) else return err; // handle EndOfStream gracefully
        };

        try stderr.print("Received: {s}\n", .{buffer.items});
        try stderr_bw.flush();

        try stdout.print("{s}\n", .{buffer.items});
        try bw.flush(); // Don't forget to flush!

        buffer.clearRetainingCapacity();
    }
}
