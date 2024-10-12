const std = @import("std");

const BodyType = enum {
    init,
    init_ok,
    echo,
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
    echo: struct {},
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

// TODO: accept global node options and build respond message with correct node id
pub fn buildInitReply(init_message: Message) Message {
    const body = Body{ .init_ok = .{ .in_reply_to = init_message.body.init.msg_id } };
    return .{ .src = init_message.dest, .dest = init_message.src, .body = body };
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
                .init_ok => .{ .init_ok = undefined },
                .echo => .{ .echo = undefined },
            };

            const message: Message = .{
                .src = parsed.value.object.get("src").?.string,
                .dest = parsed.value.object.get("dest").?.string,
                .body = message_body,
            };

            switch (body_type) {
                .init => {
                    const reply = buildInitReply(message);
                    try std.json.stringify(reply, .{}, stdout);
                    try bw.flush(); // Don't forget to flush!
                },
                else => {},
            }
        } else |_| {} // if error happened during parsing, do nothing and process next message
    }
}
