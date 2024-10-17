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

    input_buffer: std.ArrayList(u8),
    output_buffer: std.io.BufferedWriter(4096, std.io.AnyWriter),
    log_buffer: std.io.BufferedWriter(4096, std.io.AnyWriter),

    pub fn init(allocator: Allocator, inp: std.io.AnyReader, out: std.io.AnyWriter, log: std.io.AnyWriter) Node {
        const buffer = std.ArrayList(u8).init(allocator);

        const output_buffer = std.io.bufferedWriter(out);
        const log_buffer = std.io.bufferedWriter(log);

        return .{
            .allocator = allocator,
            .inp = inp,
            .out = out,
            .log = log,

            .input_buffer = buffer,
            .output_buffer = output_buffer,
            .log_buffer = log_buffer,
        };
    }

    pub fn deinit(self: *Node) void {
        self.input_buffer.deinit();
    }

    fn receiveMessage(self: *Node) !?std.json.Parsed(com.Message) {
        self.inp.streamUntilDelimiter(self.input_buffer.writer(), '\n', null) catch |err| {
            if (err == error.EndOfStream) std.process.exit(0) else return err; // handle EndOfStream gracefully
        };
        defer self.input_buffer.clearRetainingCapacity();

        const parsedValue = std.json.parseFromSlice(std.json.Value, self.allocator, self.input_buffer.items, .{ .allocate = .alloc_if_needed }) catch return null;
        defer parsedValue.deinit();

        const parsedMessage = std.json.parseFromValue(com.Message, self.allocator, parsedValue.value, .{ .allocate = .alloc_always }) catch return null;

        return parsedMessage;
    }

    fn sendMessage(self: *Node, message: com.Message) !void {
        const writer = self.output_buffer.writer();
        try std.json.stringify(message, .{}, writer);
        try writer.print("\n", .{});
        try self.output_buffer.flush();
    }

    fn logReceived(self: *Node, message: com.Message) !void {
        const writer = self.log_buffer.writer();
        try writer.print("Received: ", .{});
        try std.json.stringify(message, .{}, writer);
        try writer.print("\n", .{});
        try self.log_buffer.flush();
    }

    pub fn run(self: *Node) !void {
        while (true) {
            const maybeParsedMessage = try self.receiveMessage();

            if (maybeParsedMessage) |parsedMessage| {
                defer parsedMessage.deinit();
                const message = parsedMessage.value;

                try self.logReceived(message);

                switch (message.body) {
                    .init => {
                        const reply = buildInitReply(message);
                        try self.sendMessage(reply);
                    },
                    .echo => {
                        const reply = buildEchoReply(message);
                        try self.sendMessage(reply);
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
