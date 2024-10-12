const std = @import("std");

const BodyType = enum {
    init,
    init_ok,
    echo,
    echo_ok,
};

const Body = union(BodyType) {
    init: struct {
        type: []const u8 = "init",
        msg_id: i64,
        node_id: []const u8,
        node_ids: [][]const u8,
    },
    init_ok: struct {
        type: []const u8 = "init_ok",
        in_reply_to: i64,
    },
    echo: struct {
        type: []const u8 = "echo",
        echo: []const u8,
        msg_id: i64,
    },
    echo_ok: struct {
        type: []const u8 = "echo_ok",
        echo: []const u8,
        msg_id: i64,
        in_reply_to: i64,
    },
};

const Message = struct {
    src: []const u8,
    dest: []const u8,
    body: Body,

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try jw.beginObject();

        try jw.objectField("src");
        try jw.write(self.src);

        try jw.objectField("dest");
        try jw.write(self.dest);

        try jw.objectField("body");
        switch (self.body) {
            inline else => |body| {
                try jw.write(body);
            },
        }

        try jw.endObject();
    }
};

var message_counter: usize = 0;

// TODO: accept global node options and build respond message with correct node id
pub fn buildInitReply(init_message: Message) Message {
    const body = Body{ .init_ok = .{ .in_reply_to = init_message.body.init.msg_id } };
    return .{ .src = init_message.dest, .dest = init_message.src, .body = body };
}

// TODO: accept global node options and build respond message with correct node id
// HACK: global message counter, not thread safe
pub fn buildEchoReply(echo_message: Message) Message {
    const body = Body{ .echo_ok = .{ .echo = echo_message.body.echo.echo, .in_reply_to = echo_message.body.echo.msg_id, .msg_id = @intCast(message_counter) } };
    message_counter += 1;
    return .{ .src = echo_message.dest, .dest = echo_message.src, .body = body };
}

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
        defer buffer.clearRetainingCapacity();

        try stderr.print("Received: {s}\n", .{buffer.items});
        try stderr_bw.flush();

        if (std.json.parseFromSlice(std.json.Value, allocator, buffer.items, .{ .allocate = .alloc_if_needed })) |parsed| {
            defer parsed.deinit();

            const body = parsed.value.object.get("body").?.object;
            const body_type_str = body.get("type").?.string;
            const body_type = std.meta.stringToEnum(BodyType, body_type_str) orelse return;

            const message_body: Body = switch (body_type) {
                .init => blk: {
                    const node_ids_values = body.get("node_ids").?.array;
                    const node_ids: [][]const u8 = try allocator.alloc([]const u8, node_ids_values.items.len); // TODO: need to free it later
                    for (0.., node_ids_values.items) |i, item| {
                        node_ids[i] = item.string;
                    }
                    break :blk .{ .init = .{ .msg_id = body.get("msg_id").?.integer, .node_id = body.get("node_id").?.string, .node_ids = node_ids } };
                },
                .echo => blk: {
                    break :blk .{ .echo = .{ .echo = body.get("echo").?.string, .msg_id = body.get("msg_id").?.integer } };
                },
                inline else => |body_type_enum| blk: {
                    break :blk @unionInit(Body, @tagName(body_type_enum), undefined);
                },
            };

            const message: Message = .{
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
                    try stderr_bw.flush();

                    try std.json.stringify(reply, .{}, stdout);
                    try stdout.print("\n", .{});
                    try bw.flush(); // Don't forget to flush!
                },
                .echo => {
                    const reply = buildEchoReply(message);

                    try stderr.print("Responding: ", .{});
                    try std.json.stringify(reply, .{}, stderr);
                    try stderr.print("\n", .{});
                    try stderr_bw.flush();

                    try std.json.stringify(reply, .{}, stdout);
                    try stdout.print("\n", .{});
                    try bw.flush();
                },
                else => {},
            }
        } else |_| {} // if error happened during parsing, do nothing and process next message
    }
}
