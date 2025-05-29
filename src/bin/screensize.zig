const thr = @import("thermit");
const std = @import("std");

pub fn main() !void {
    var tty = try thr.Terminal.init(std.io.getStdErr());
    defer tty.deinit();

    const wr = tty.f.writer();

    try tty.enableRawMode();
    defer tty.disableRawMode() catch unreachable;

    try thr.enterAlternateScreen(wr);
    defer thr.leaveAlternateScreen(wr) catch unreachable;

    var renders: u16 = 0;

    var sz = try thr.getWindowSize(tty.f.handle);

    renders += 1;
    try draw(wr, sz, renders);

    while (true) {
        const e = try tty.read(std.math.maxInt(i32));
        var drw = false;
        var end = false;

        switch (e) {
            .Key => |key| end = (thr.keys.bits(key) == 'q'),
            .End => end = true,
            .Resize => {
                sz = try thr.getWindowSize(tty.f.handle);
                drw = true;
            },
            .Timeout, .Unknown => {},
        }
        if (end) return;

        if (drw) {
            renders += 1;
            try draw(wr, sz, renders);
        }
    }
}

pub fn draw(wr: anytype, sz: thr.Size, renders: u16) !void {
    var buf = std.io.bufferedWriter(wr);
    const bufw = buf.writer();

    try thr.clear(bufw, .All);
    try thr.moveTo(bufw, 0, 0);

    try std.fmt.format(bufw, "Press [q] to quit\n", .{});
    try std.fmt.format(bufw, "Renders: {}\n", .{renders});
    try std.fmt.format(bufw, "Window Size: {}, {}\n", sz);

    try buf.flush();
}
