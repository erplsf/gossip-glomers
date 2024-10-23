const std = @import("std");
const Allocator = std.mem.Allocator;
const Node = @import("node").Node;
const Message = @import("common").Message;
const WrappedMessage = @import("common").WrappedMessage;

const EchoHandler = struct {
    message_counter: usize = 0,

    // TODO: accept global node options and build respond message with correct node id
    // HACK: global message counter, not thread safe
    pub fn handle_echo(self: *@This(), node: *Node(@This()), echo_message: Message) !?WrappedMessage {
        _ = node;
        defer self.message_counter += 1;

        const body = .{ .echo_ok = .{ .echo = echo_message.body.echo.echo, .in_reply_to = echo_message.body.echo.msg_id, .msg_id = @as(i64, @intCast(self.message_counter)) } };
        return .{ .message = .{ .src = echo_message.dest, .dest = echo_message.src, .body = body } };
    }
};

pub fn main() !void {
    const stdin = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer().any();
    const stderr = std.io.getStdErr().writer().any();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var node = Node(EchoHandler).init(allocator, stdin, stdout, stderr);
    defer node.deinit();

    try node.run();
}
