//! Declarative commands on top of the generated `command` interface.
//!
//!     try pumpkin.cmd.register(ctx, .{
//!         .names = &.{ "greet", "hi" },
//!         .description = "Greets players.",
//!         .permission = "my-plugin:command.greet",
//!         .run = greetSelf,
//!         .then = &.{
//!             .argument("targets", .players, .{ .run = greetTargets }),
//!         },
//!     });

const std = @import("std");
const abi = @import("abi.zig");
const wit = @import("wit.zig");

const command = wit.command;
const Context = wit.context.Context;
const Server = wit.server.Server;
const TextComponent = wit.text.TextComponent;

pub const Sender = command.CommandSender;
pub const Args = command.ConsumedArgs;
pub const Arg = command.Arg;
pub const ArgumentType = command.ArgumentType;
pub const Result = abi.Result(i32, command.CommandError);

pub const Handler = fn (Sender, Server, Args) Result;
pub const Suggester = fn (Sender, Server, command.SuggestionRequest) command.CommandSuggestions;

pub const Node = struct {
    kind: union(enum) {
        literal: []const u8,
        argument: struct { name: []const u8, type: ArgumentType },
    },
    options: Options,

    pub const Options = struct {
        run: ?*const Handler = null,
        /// Only meaningful on arguments.
        suggest: ?*const Suggester = null,
        then: []const Node = &.{},
    };

    pub fn literal(name: []const u8, options: Options) Node {
        return .{ .kind = .{ .literal = name }, .options = options };
    }

    pub fn argument(name: []const u8, arg_type: ArgumentType, options: Options) Node {
        return .{ .kind = .{ .argument = .{ .name = name, .type = arg_type } }, .options = options };
    }

    fn build(node: Node) command.CommandNode {
        const built: command.CommandNode = switch (node.kind) {
            .literal => |name| .literal(name),
            .argument => |arg| .argument(arg.name, arg.type),
        };
        if (node.options.run) |handler| built.executeWithHandlerId(@intFromPtr(handler));
        if (node.options.suggest) |suggester| built.suggestWithHandlerId(@intFromPtr(suggester));
        for (node.options.then) |child| built.then(child.build());
        return built;
    }
};

pub const Spec = struct {
    /// The command's name followed by its aliases.
    names: []const []const u8,
    description: []const u8 = "",
    /// Has to start with "<plugin name>:". A node the server has never heard
    /// of denies everyone, so `register` registers it as well.
    permission: []const u8,
    default: wit.permission.PermissionDefault = .allow,
    run: ?*const Handler = null,
    then: []const Node = &.{},
};

pub fn register(ctx: Context, spec: Spec) error{PermissionRejected}!void {
    switch (ctx.registerPermission(.{
        .node = spec.permission,
        .description = spec.description,
        .default = spec.default,
        .children = &.{},
    })) {
        .ok => {},
        .err => |message| {
            std.log.err("permission {s}: {s}", .{ spec.permission, message });
            return error.PermissionRejected;
        },
    }

    const root: command.Command = .init(spec.names, spec.description);
    if (spec.run) |handler| root.executeWithHandlerId(@intFromPtr(handler));
    for (spec.then) |child| root.then(child.build());
    ctx.registerCommand(root, spec.permission);
}

pub fn ok(count: i32) Result {
    return .{ .ok = count };
}

pub fn fail(message: []const u8) Result {
    return .{ .err = .{ .command_failed = .text(message) } };
}

/// The value of argument `name` if it was parsed as `tag`.
pub fn get(args: Args, name: []const u8, comptime tag: std.meta.Tag(Arg)) ?@FieldType(Arg, @tagName(tag)) {
    const value = args.getValue(name);
    return if (value == tag) @field(value, @tagName(tag)) else null;
}

/// Any numeric argument as an integer, null when missing or out of bounds.
pub fn int(args: Args, name: []const u8) ?i64 {
    return switch ((get(args, name, .num) orelse return null)) {
        .ok => |number| switch (number) {
            .int32 => |v| v,
            .int64 => |v| v,
            .float32 => |v| @intFromFloat(v),
            .float64 => |v| @intFromFloat(v),
        },
        .err => null,
    };
}

pub fn float(args: Args, name: []const u8) ?f64 {
    return switch ((get(args, name, .num) orelse return null)) {
        .ok => |number| switch (number) {
            .int32 => |v| @floatFromInt(v),
            .int64 => |v| @floatFromInt(v),
            .float32 => |v| v,
            .float64 => |v| v,
        },
        .err => null,
    };
}

/// Suggests `values` for the word under the cursor.
pub fn suggestions(request: command.SuggestionRequest, values: []const []const u8) command.CommandSuggestions {
    const out = abi.arena().alloc(command.CommandSuggestion, values.len) catch @panic("OOM");
    var n: usize = 0;
    for (values) |value| {
        if (!std.mem.startsWith(u8, value, request.remaining)) continue;
        out[n] = .{ .value = value, .tooltip = null };
        n += 1;
    }
    return .{ .start = request.start, .length = @intCast(request.remaining.len), .values = out[0..n] };
}
