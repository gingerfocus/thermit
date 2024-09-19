const thermit = @import("thermit");
const std = @import("std");

pub fn main() !void {
    var tty = try thermit.Terminal.init(std.io.getStdErr());
    defer tty.deinit();

    const wr = tty.f.writer();

    try tty.enableRawMode();
    defer tty.disableRawMode() catch unreachable;

    try thermit.enterAlternateScreen(wr);
    defer thermit.leaveAlternateScreen(wr) catch unreachable;

    var renders: u16 = 0;

    var sz = try thermit.getWindowSize(tty.f.handle);
    // var x, var y = try thermit.getWindowSize(tty.f.handle);

    renders += 1;
    try draw(wr, sz, renders);

    while (true) {
        const e = try tty.read(std.math.maxInt(i32));
        var drw = false;
        var end = false;

        switch (e) {
            // This is not recomended: however, it works beacuse if `eventtype`
            // is anything other than Char then character must be 0, which
            // still gives the correct result.
            .Key => |ke| end = (ke.character == 'q'),
            .End => end = true,
            .Resize => |size| {
                sz = size;
                drw = true;
            },
            .Timeout => {},
            .Unknown => {},
        }
        if (end) return;

        if (drw) {
            renders += 1;
            try draw(wr, sz, renders);
        }
    }
}

pub fn draw(wr: anytype, sz: thermit.Size, renders: u16) !void {
    var buf = std.io.bufferedWriter(wr);
    const bufw = buf.writer();

    try thermit.clear(bufw, .All);
    try thermit.moveTo(bufw, 0, 0);

    try std.fmt.format(bufw, "Press [q] to quit\n", .{});
    try std.fmt.format(bufw, "Renders: {}\n", .{renders});
    try std.fmt.format(bufw, "Window Size: {}, {}\n", sz);

    try buf.flush();
}
