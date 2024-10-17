const std = @import("std");
const Allocator = std.mem.Allocator;
const com = @import("common");
const Node = @import("node").Node;

const EchoHandler = struct {
    message_counter: usize = 0,

    // TODO: accept global node options and build respond message with correct node id
    // HACK: global message counter, not thread safe
    pub fn handle_echo(self: *EchoHandler, node: *Node(EchoHandler), echo_message: com.Message) !?com.Message {
        _ = node;
        const body = com.Body{ .echo_ok = .{ .echo = echo_message.body.echo.echo, .in_reply_to = echo_message.body.echo.msg_id, .msg_id = @intCast(self.message_counter) } };
        self.message_counter += 1;
        return .{ .src = echo_message.dest, .dest = echo_message.src, .body = body };
    }
};

pub fn main() !void {
    const stdin = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer().any();
    const stderr = std.io.getStdErr().writer().any();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var node = Node(EchoHandler).init(allocator, stdin, stdout, stderr, EchoHandler{});
    try node.run();
}
