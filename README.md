# Pumpkin API for Zig

This package provides Zig bindings for building Pumpkin plugins using WebAssembly (Wasm) components.

You will need [Zig](https://ziglang.org/download/) 0.16.0 and [`wasm-tools`](https://github.com/bytecodealliance/wasm-tools) in your `PATH`.

## Quick Start

1. Setup Your Project

Add the package to your project:

```sh
zig fetch --save git+https://github.com/Pumpkin-MC/pumpkin-api-zig
```

Create a `build.zig` for your plugin:

```zig
const std = @import("std");
const pumpkin_api = @import("pumpkin_api_zig");

pub fn build(b: *std.Build) void {
    _ = pumpkin_api.addPlugin(b, b.dependency("pumpkin_api_zig", .{}), .{
        .name = "pumpkin-plugin-example",
        .root_source_file = b.path("src/main.zig"),
    });
}
```

2. Write Your Plugin

Create your source file (e.g. `src/main.zig`):

```zig
const std = @import("std");
const pumpkin = @import("pumpkin");

pub const std_options: std.Options = .{ .logFn = pumpkin.logFn };

const MyPlugin = struct {
    pub const metadata: pumpkin.Metadata = .{
        .name = "pumpkin-plugin-example",
        .version = "0.1.0",
        .authors = &.{"You"},
        .description = "An example plugin in Zig.",
    };

    pub const events = .{
        .player_join_event = onJoin,
    };

    pub fn onLoad(_: pumpkin.Context) !void {
        std.log.info("Hello from Zig!", .{});
    }

    fn onJoin(_: pumpkin.Server, ev: *pumpkin.EventData(.player_join_event)) void {
        std.log.info("{s} joined", .{ev.player.getName()});
    }
};

comptime {
    pumpkin.register(MyPlugin);
}
```

Everything the API returns, handles included, is only valid until the current callback returns. Call `keep()` on a handle to hold on to it, then release it with `deinit()` when you're done.

3. Build Your Plugin

Compile your plugin into a WebAssembly component:

```sh
zig build
```

This will produce `zig-out/pumpkin-plugin-example.wasm` ready to be loaded into Pumpkin.
