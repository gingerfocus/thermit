const scinee = @import("scinee");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var term = try scinee.Term.init(a);
    defer term.deinit();

    const start = std.time.milliTimestamp();

    try term.start(false);
    try fullRedraw(&term, start);
    try term.finish();

    while (true) {
        const ev = try term.tty.read(100);

        var full = false;
        switch (ev) {
            .Key => |ke| if (ke.character == 'q') break,
            .Resize => full = true,
            else => {},
        }

        try term.start(full);
        if (full) try fullRedraw(&term, start) //
        else try screenRedraw(&term, start); //

        try term.finish();
    }

    // std.time.sleep(std.time.ns_per_s * 3);
}

const statusbarHeight = 3;
const sidebarWidth = 5;

fn fullRedraw(term: *scinee.Term, start: i64) !void {

    // line numbers
    const leftside = .{
        .x = 0,
        .y = 0,
        .w = sidebarWidth,
        .h = term.size[1] - statusbarHeight,
    };

    for (0..leftside.h) |r| {
        var buf: [4]u8 = .{ ' ', ' ', ' ', '|' };
        const out = try std.fmt.bufPrint(&buf, "{}", .{r});
        std.debug.assert(out.len < 3);
        term.draw(leftside, @intCast(r), 1, &buf);
    }

    const statusbar = .{
        .x = 0,
        .y = term.size[1] - statusbarHeight,
        .w = term.size[0],
        .h = statusbarHeight,
    };

    var buf: [256]u8 = undefined;
    @memset(&buf, '>');
    term.draw(statusbar, 0, 0, buf[0..statusbar.w]);

    term.draw(statusbar, 1, 3, "footer text");
    term.draw(statusbar, 2, 6, "animation example");

    try screenRedraw(term, start);
}

fn screenRedraw(term: *scinee.Term, start: i64) !void {
    const mainscreen = .{
        .x = sidebarWidth,
        .y = 0,
        .w = term.size[0] - sidebarWidth,
        .h = term.size[1] - statusbarHeight,
    };

    const now = std.time.milliTimestamp();
    const diff: f64 = @floatFromInt(now - start);

    for (0..mainscreen.h) |r| {
        var buf: [256]u8 = undefined;
        for (&buf, 0..) |*b, i| {
            const d: f64 = @floatFromInt(r * 256 + i);
            const d2 = std.math.pow(f64, 1.01, d);
            const cd = @cos(d2);
            const sd = @sin(diff);
            const l = cd + sd;
            b.* = if (l < 0.2) ' ' else if (l < 1.0) '.' else '0';
        }
        const row: u16 = @intCast(r);
        term.draw(mainscreen, row, 0, &buf);
    }
}
