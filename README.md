# Thermit
The most minimal terminal library you didnt know you needed.

## Installing
```bash
zig fetch --save=terminal git+https://github.com/gingerfocus/thermit
```

```zig
const terminal = b.dependency("terminal", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("scured", terminal.module("scured"));
```

Set the log function to not pollute the terminal, alternativly see `scu.log.logFile`
```zig
const scu = @import("scured");

pub const std_options: std.Options = .{
    .logFn = scu.log.logNull,
};
```

## Examples
```bash
zig run example-screensize
zig run example-tuianimation
```
```zig
var term = try scu.Term.init(allocator);
defer term.deinit();

try term.start(false); // clears the render buffer

const fullScreen = term.makeScreen(0, 0, null, null);
term.writeBuffer(fullScreen, 0, 0, "hello world");

term.getCell(0, 1).?.setSymbol('本');

try term.finish(); // flushes the render buffer

while (true) {
    const ev = try term.tty.read(1000);
    switch (ev) {
        .Key => |key| if (key.character.b() == 'q') break,
        else => {},
    }
}
```

