const std = @import("std");
const Allocator = std.mem.Allocator;
const com = @import("common");

var message_counter: usize = 0;

// TODO: accept global node options and build respond message with correct node id
pub fn buildInitReply(init_message: com.Message) com.Message {
    const body = com.Body{ .init_ok = .{ .in_reply_to = init_message.body.init.msg_id } };
    return .{ .src = init_message.dest, .dest = init_message.src, .body = body };
}

// TODO: accept global node options and build respond message with correct node id
// HACK: global message counter, not thread safe
pub fn buildEchoReply(echo_message: com.Message) com.Message {
    const body = com.Body{ .echo_ok = .{ .echo = echo_message.body.echo.echo, .in_reply_to = echo_message.body.echo.msg_id, .msg_id = @intCast(message_counter) } };
    message_counter += 1;
    return .{ .src = echo_message.dest, .dest = echo_message.src, .body = body };
}

const Node = struct {
    allocator: Allocator,
    inp: std.io.AnyReader,
    out: std.io.AnyWriter,
    log: std.io.AnyWriter,

    pub fn init(allocator: Allocator, inp: std.io.AnyReader, out: std.io.AnyWriter, log: std.io.AnyWriter) Node {
        return .{ .allocator = allocator, .inp = inp, .out = out, .log = log };
    }

    pub fn run(self: *Node) !void {
        var stdout_buffer = std.io.bufferedWriter(self.out);
        const stdout = stdout_buffer.writer();

        var stderr_buffer = std.io.bufferedWriter(self.log);
        const stderr = stderr_buffer.writer();

        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        while (true) {
            self.inp.streamUntilDelimiter(buffer.writer(), '\n', null) catch |err| {
                if (err == error.EndOfStream) std.process.exit(0) else return err; // handle EndOfStream gracefully
            };
            defer buffer.clearRetainingCapacity();

            try stderr.print("Received: {s}\n", .{buffer.items});
            try stderr_buffer.flush();

            if (std.json.parseFromSlice(std.json.Value, self.allocator, buffer.items, .{ .allocate = .alloc_if_needed })) |parsed| {
                defer parsed.deinit();

                const parsedMessage = try std.json.parseFromValue(com.Message, self.allocator, parsed.value, .{ .allocate = .alloc_if_needed });
                defer parsedMessage.deinit();

                const message: com.Message = parsedMessage.value;

                switch (message.body) {
                    .init => {
                        const reply = buildInitReply(message);

                        try stderr.print("Responding: ", .{});
                        try std.json.stringify(reply, .{}, stderr);
                        try stderr.print("\n", .{});
                        try stderr_buffer.flush();

                        try std.json.stringify(reply, .{}, stdout);
                        try stdout.print("\n", .{});
                        try stdout_buffer.flush(); // Don't forget to flush!
                    },
                    .echo => {
                        const reply = buildEchoReply(message);

                        try stderr.print("Responding: ", .{});
                        try std.json.stringify(reply, .{}, stderr);
                        try stderr.print("\n", .{});
                        try stderr_buffer.flush();

                        try std.json.stringify(reply, .{}, stdout);
                        try stdout.print("\n", .{});
                        try stdout_buffer.flush();
                    },
                    else => {},
                }
            } else |_| {} // if error happened during parsing, do nothing and process next message
        }
    }
};

pub fn main() !void {
    const stdin = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer().any();
    const stderr = std.io.getStdErr().writer().any();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var node = Node.init(allocator, stdin, stdout, stderr);
    try node.run();
}
