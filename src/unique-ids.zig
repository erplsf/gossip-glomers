const std = @import("std");
const Allocator = std.mem.Allocator;
const com = @import("common");
const Node = @import("node").Node;

const UniqueIdsHandler = struct {
    message_counter: usize = 0,

    // TODO: accept global node options and build respond message with correct node id
    // HACK: global message counter, not thread safe
    // FIXME: leaks memory
    pub fn handle_generate(self: *UniqueIdsHandler, node: *Node(UniqueIdsHandler), message: com.Message) !?com.Message {
        const id = try std.fmt.allocPrint(node.allocator, "{s}-{d}", .{ message.dest, @as(usize, @intCast(self.message_counter)) });
        const body = com.Body{ .generate_ok = .{ .id = id, .in_reply_to = message.body.generate.msg_id } };
        self.message_counter += 1;
        return .{ .src = message.dest, .dest = message.src, .body = body };
    }
};

pub fn main() !void {
    const stdin = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer().any();
    const stderr = std.io.getStdErr().writer().any();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var node = Node(UniqueIdsHandler).init(allocator, stdin, stdout, stderr, UniqueIdsHandler{});
    try node.run();
}
