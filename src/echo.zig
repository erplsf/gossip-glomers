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

                const body = parsed.value.object.get("body").?.object;
                const body_type_str = body.get("type").?.string;
                const body_type = std.meta.stringToEnum(com.BodyType, body_type_str) orelse return;

                const message_body: com.Body = switch (body_type) {
                    .init => blk: {
                        const node_ids_values = body.get("node_ids").?.array;
                        const node_ids: [][]const u8 = try self.allocator.alloc([]const u8, node_ids_values.items.len); // TODO: need to free it later
                        for (0.., node_ids_values.items) |i, item| {
                            node_ids[i] = item.string;
                        }
                        break :blk .{ .init = .{ .msg_id = body.get("msg_id").?.integer, .node_id = body.get("node_id").?.string, .node_ids = node_ids } };
                    },
                    .echo => blk: {
                        break :blk .{ .echo = .{ .echo = body.get("echo").?.string, .msg_id = body.get("msg_id").?.integer } };
                    },
                    inline else => |body_type_enum| blk: {
                        break :blk @unionInit(com.Body, @tagName(body_type_enum), undefined);
                    },
                };

                const message: com.Message = .{
                    .src = parsed.value.object.get("src").?.string,
                    .dest = parsed.value.object.get("dest").?.string,
                    .body = message_body,
                };

                switch (body_type) {
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
