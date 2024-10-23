const std = @import("std");

pub const BodyType = enum {
    init,
    init_ok,
    echo,
    echo_ok,
    generate,
    generate_ok,
    topology,
    topology_ok,
};

pub const Body = union(BodyType) {
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
    generate: struct {
        type: []const u8 = "generate",
        msg_id: i64,
    },
    generate_ok: struct {
        type: []const u8 = "generate_ok",
        in_reply_to: i64,
        id: []const u8,
    },
    topology: struct {
        type: []const u8 = "topology",
        topology: std.json.ArrayHashMap([][]const u8),
    },
    topology_ok: struct {
        type: []const u8 = "topology_ok",
    },

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, value: std.json.Value, options: std.json.ParseOptions) !Body {
        const body_type = value.object.get("type").?.string;

        const type_info = @typeInfo(Body).@"union";
        inline for (type_info.fields) |field| {
            if (std.mem.eql(u8, field.name, body_type)) {
                return @unionInit(Body, field.name, try std.json.innerParseFromValue(field.type, allocator, value, options));
            }
        }

        return error.UnknownField;
    }
};

pub const Message = struct {
    id: ?i64 = null, // HACK: received with all messages but we don't really care about it
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
            inline else => |body| try jw.write(body),
        }

        try jw.endObject();
    }
};

pub const WrappedMessage = struct {
    message: Message,
    allocator: ?std.heap.ArenaAllocator = null,

    pub fn deinit(self: *@This()) void {
        if (self.allocator) |allocator| allocator.deinit();
    }
};
