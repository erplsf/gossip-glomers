const std = @import("std");
const Allocator = std.mem.Allocator;
const com = @import("common");

pub fn Node(comptime T: type) type {
    return struct {
        allocator: Allocator,
        inp: std.io.AnyReader,
        out: std.io.AnyWriter,
        log: std.io.AnyWriter,

        handler: T,

        input_buffer: std.ArrayList(u8),
        output_buffer: std.io.BufferedWriter(4096, std.io.AnyWriter),
        log_buffer: std.io.BufferedWriter(4096, std.io.AnyWriter),

        pub fn init(allocator: Allocator, inp: std.io.AnyReader, out: std.io.AnyWriter, log: std.io.AnyWriter, handler: T) @This() {
            const buffer = std.ArrayList(u8).init(allocator);

            const output_buffer = std.io.bufferedWriter(out);
            const log_buffer = std.io.bufferedWriter(log);

            return .{
                .allocator = allocator,
                .inp = inp,
                .out = out,
                .log = log,

                .handler = handler,

                .input_buffer = buffer,
                .output_buffer = output_buffer,
                .log_buffer = log_buffer,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.input_buffer.deinit();
        }

        // TODO: accept global node options and build respond message with correct node id
        pub fn buildInitReply(init_message: com.Message) com.Message {
            const body = com.Body{ .init_ok = .{ .in_reply_to = init_message.body.init.msg_id } };
            return .{ .src = init_message.dest, .dest = init_message.src, .body = body };
        }

        fn receiveMessage(self: *@This()) !?std.json.Parsed(com.Message) {
            try self.inp.streamUntilDelimiter(self.input_buffer.writer(), '\n', null);
            defer self.input_buffer.clearRetainingCapacity();

            const writer = self.log_buffer.writer();
            try writer.print("Raw received text: {s}\n", .{self.input_buffer.items});
            try self.log_buffer.flush();

            const parsedValue = std.json.parseFromSlice(std.json.Value, self.allocator, self.input_buffer.items, .{ .allocate = .alloc_if_needed }) catch return null;
            defer parsedValue.deinit();

            const parsedMessage = try std.json.parseFromValue(com.Message, self.allocator, parsedValue.value, .{ .allocate = .alloc_always });

            return parsedMessage;
        }

        fn sendMessage(self: *@This(), message: com.Message) !void {
            const writer = self.output_buffer.writer();
            try std.json.stringify(message, .{}, writer);
            try writer.print("\n", .{});
            try self.output_buffer.flush();
        }

        fn logReceived(self: *@This(), message: com.Message) !void {
            const writer = self.log_buffer.writer();
            try writer.print("Received message: ", .{});
            try std.json.stringify(message, .{}, writer);
            try writer.print("\n", .{});
            try self.log_buffer.flush();
        }

        fn logReply(self: *@This(), message: com.Message) !void {
            const writer = self.log_buffer.writer();
            try writer.print("Replying with: ", .{});
            try std.json.stringify(message, .{}, writer);
            try writer.print("\n", .{});
            try self.log_buffer.flush();
        }

        pub fn run(self: *@This()) !void {
            while (true) {
                const maybeParsedMessage = self.receiveMessage() catch |err| {
                    if (err == error.EndOfStream) break else return err; // stop running if the input stream is closed, otherwise just bubble up the error
                };

                if (maybeParsedMessage) |parsedMessage| {
                    defer parsedMessage.deinit();
                    const message = parsedMessage.value;

                    try self.logReceived(message);

                    switch (message.body) {
                        .init => {
                            const reply = buildInitReply(message);
                            try self.logReply(reply);
                            try self.sendMessage(reply);
                        },
                        inline else => |_, tag| {
                            const fn_name = "handle_" ++ @tagName(tag);
                            if (std.meta.hasFn(T, fn_name)) {
                                const field = @field(T, fn_name);
                                const maybeReply = try @call(.auto, field, .{ &self.handler, self, message });
                                if (maybeReply) |reply| {
                                    try self.logReply(reply);
                                    try self.sendMessage(reply);
                                }
                            }
                        },
                    }
                }
            }
        }
    };
}
