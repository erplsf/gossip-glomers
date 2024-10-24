const std = @import("std");
const Allocator = std.mem.Allocator;
const Message = @import("common").Message;
const WrappedMessage = @import("common").WrappedMessage;
const Node = @import("node").Node;

const BroadcastHandler = struct {
    message_counter: usize = 0,
    messages: std.ArrayList(usize) = undefined,

    pub fn init(allocator: Allocator) @This() {
        const messages = std.ArrayList(usize).init(allocator);
        return .{
            .messages = messages,
        };
    }

    pub fn handle_topology(self: *@This(), node: *Node(@This()), message: Message) !?WrappedMessage {
        _ = self;
        _ = node;
        return .{ .message = .{ .src = message.dest, .dest = message.src, .body = .{ .topology_ok = .{ .in_reply_to = message.body.topology.msg_id } } } };
    }

    // TODO: accept global node options and build respond message with correct node id
    // HACK: global message counter, not thread safe
    // pub fn handle_generate(self: *BroadcastHandler, node: *Node(BroadcastHandler), message: com.Message) !?com.Message {
    //     const id = try std.fmt.allocPrint(node.allocator, "{s}-{d}", .{ message.dest, @as(usize, @intCast(self.message_counter)) });
    //     const body = com.Body{ .generate_ok = .{ .id = id, .in_reply_to = message.body.generate.msg_id } };
    //     self.message_counter += 1;
    //     return .{ .src = message.dest, .dest = message.src, .body = body };
    // }

    pub fn deinit(self: *@This()) void {
        self.messages.deinit();
    }
};

pub fn main() !void {
    const stdin = std.io.getStdIn().reader().any();
    const stdout = std.io.getStdOut().writer().any();
    const stderr = std.io.getStdErr().writer().any();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var node = Node(BroadcastHandler).init(allocator, stdin, stdout, stderr);
    defer node.deinit();

    try node.run();
}
