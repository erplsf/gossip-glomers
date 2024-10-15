pub const BodyType = enum {
    init,
    init_ok,
    echo,
    echo_ok,
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
};

pub const Message = struct {
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
