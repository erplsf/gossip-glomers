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

    buffer: std.ArrayList(u8),

    pub fn init(allocator: Allocator, inp: std.io.AnyReader, out: std.io.AnyWriter, log: std.io.AnyWriter) Node {
        const buffer = std.ArrayList(u8).init(allocator);
        return .{
            .allocator = allocator,
            .inp = inp,
            .out = out,
            .log = log,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *Node) void {
        self.buffer.deinit();
    }

    fn receiveMessage(self: *Node) !?std.json.Parsed(com.Message) {
        self.inp.streamUntilDelimiter(self.buffer.writer(), '\n', null) catch |err| {
            if (err == error.EndOfStream) std.process.exit(0) else return err; // handle EndOfStream gracefully
        };
        defer self.buffer.clearRetainingCapacity();

        const parsedValue = std.json.parseFromSlice(std.json.Value, self.allocator, self.buffer.items, .{ .allocate = .alloc_if_needed }) catch return null;
        defer parsedValue.deinit();

        const parsedMessage = std.json.parseFromValue(com.Message, self.allocator, parsedValue.value, .{ .allocate = .alloc_always }) catch return null;

        return parsedMessage;
    }

    pub fn run(self: *Node) !void {
        var stdout_buffer = std.io.bufferedWriter(self.out);
        const stdout = stdout_buffer.writer();

        var stderr_buffer = std.io.bufferedWriter(self.log);
        const stderr = stderr_buffer.writer();

        while (true) {
            const maybeParsedMessage = try self.receiveMessage();

            if (maybeParsedMessage) |parsedMessage| {
                defer parsedMessage.deinit();
                const message = parsedMessage.value;

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
            }
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
