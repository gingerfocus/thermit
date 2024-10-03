# Thermit
The most minimal terminal library you didnt know you needed.


## Installing
```bash
zig fetch --save=thermit git+https://github.com/gingerfocus/thermit
```

```zig
const thermit = b.dependency("thermit", .{ .target = target, .optimize = optimize });
// exe.root_module.addImport("thermit", thermit.module("thermit"));
exe.root_module.addImport("scinee", thermit.module("scinee"));
```


Set the log function to not pollute the terminal, alternativly see `scinee.log.logFile`
```zig
const scinee = @import("scinee");

pub const std_options: std.Options = .{
    .logFn = scinee.log.logNull,
};
```

## Examples
```bash
zig run example-screensize
zig run example-tuianimation
```

```zig
var term = try scinee.Term.init(allocator);
defer term.deinit();

try term.start(false); // clears the render buffer

term.getCell(0, 1).?.setSymbol('本');

const fullScreen = term.makeScreen(0, 0, null, null);
try term.draw(fullScreen, 0, 0, "hello world");

try term.finish(); // flushes the render buffer

while (true) {
    const ev = try term.tty.read(1000);
    switch (ev) {
        .Key => |key| if (key.character.b() == 'q') break,
        else => {},
    }
}
```

