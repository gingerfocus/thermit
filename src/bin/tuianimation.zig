const std = @import("std");
const scu = @import("scinee");

const trm = scu.thermit;

pub const std_options: std.Options = .{
    .logFn = scu.log.toFile,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const f = try std.fs.cwd().createFile("example.log", .{});
    defer f.close();
    scu.log.setFile(f);

    var term = try scu.Term.init(a);
    defer term.deinit();

    const start = std.time.milliTimestamp();

    try trm.cursorHide(term.tty.f.writer());
    defer trm.cursorShow(term.tty.f.writer()) catch {};

    try term.start(false);
    try fullRedraw(&term, start);
    try term.finish();

    while (true) {
        const ev = try term.tty.read(100);

        var full = false;
        switch (ev) {
            .Key => |ke| if (ke.character.b() == 'q') break,
            .Resize => full = true,
            else => {},
        }

        try term.start(full);

        if (full) try fullRedraw(&term, start) else try screenRedraw(&term, start);

        try term.finish();
    }

    // std.time.sleep(std.time.ns_per_s * 3);
}

const statbarH = 3;
const sidebarW = 5;

fn fullRedraw(term: *scu.Term, start: i64) !void {
    // line numbers
    const leftside = .{
        .x = 0,
        .y = 0,
        .w = sidebarW,
        .h = term.size[1] - statbarH,
    };

    for (0..leftside.h) |r| {
        var buf: [4]u8 = .{ ' ', ' ', ' ', '|' };
        const out = try std.fmt.bufPrint(&buf, "{}", .{r});
        std.debug.assert(out.len < 3);
        try term.draw(leftside, @intCast(r), 1, &buf);
    }

    const statusbar = term.makeScreen(0, term.size[1] - statbarH, null, statbarH);

    var buf: [256]u8 = undefined;
    @memset(&buf, '>');
    try term.draw(statusbar, 0, 0, &buf);

    try term.draw(statusbar, 1, 3, "footer text");
    try term.draw(statusbar, 2, 6, "animation example");

    try screenRedraw(term, start);
}

fn screenRedraw(term: *scu.Term, start: i64) !void {
    const mainscreen = term.makeScreen(sidebarW, 0, null, term.size[1] - statbarH);

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
        try term.draw(mainscreen, row, 0, &buf);
    }
}
