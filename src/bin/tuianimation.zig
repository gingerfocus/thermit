const std = @import("std");
const scu = @import("scured");
const trm = scu.thermit;

pub const std_options: std.Options = .{
    .logFn = scu.log.toFile,
};

pub fn main() !void {
    // see std options above on setting the log function, if you need more
    // complex logging features just make your own nerd
    const f = try std.fs.cwd().createFile("example.log", .{});
    defer f.close();
    scu.log.file = f;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var term = try scu.Term.init(a);
    defer term.deinit();

    const start = std.time.milliTimestamp();

    try term.start(true);

    try fullRedraw(&term, start);

    try term.finish();

    while (true) {
        const ev = try term.tty.read(100);

        var full = false;
        switch (ev) {
            .Key => |ke| if (trm.keys.bits(ke) == 'q') break,
            .Resize => full = true,
            else => {},
        }

        try term.start(full);

        if (full)
            try fullRedraw(&term, start)
        else
            try screenRedraw(&term, start);

        try term.finish();
    }
}

const statbarH = 3;
const sidebarW = 5;

fn fullRedraw(term: *scu.Term, start: i64) !void {
    const leftside = term.makeScreen(0, 0, sidebarW, term.size.y - statbarH);
    const statusbar = term.makeScreen(0, term.size.y - statbarH, null, statbarH);

    // ---------- Line Numbers ------------------------------------------------
    var r: u16 = 0;
    while (r < leftside.h) : (r += 1) {
        var buf: [4]u8 = .{ ' ', ' ', ' ', '|' };
        const out = try std.fmt.bufPrint(&buf, "{}", .{r});
        std.debug.assert(out.len < 3);

        var c: u16 = 1;
        for (buf) |ch| {
            if (term.getScreenCell(leftside, c, r)) |cell| cell.symbol = ch;
            c += 1;
        }
    }
    // ------------------------------------------------------------------------
    //
    //
    // ---------- Status Bar --------------------------------------------------
    var c: u16 = 0;
    while (c < statusbar.w) : (c += 1) {
        const cell = term.getScreenCell(statusbar, c, 0) orelse break;
        cell.symbol = '>';
        cell.fg = .Red;
        cell.bg = .Blue;
    }

    term.writeBuffer(statusbar, 3, 1, "footer text");
    term.writeBuffer(statusbar, 6, 2, "animation example");
    // ------------------------------------------------------------------------

    try screenRedraw(term, start);
}

fn screenRedraw(term: *scu.Term, start: i64) !void {
    const mainscreen = term.makeScreen(sidebarW, 0, null, term.size.y - statbarH);

    const cx: f32 = @floatFromInt(mainscreen.h / 2);
    const cy: f32 = @floatFromInt(mainscreen.w / 2);

    const time: f32 = @as(f32, @floatFromInt(std.time.milliTimestamp() - start));

    const SPEED = 140;

    const SPIN = 20.0;
    const INN_RADIUS = 10.0;
    const OUT_RADIUS = 17.0;

    const STRETCH = 0.5;

    const x = STRETCH * SPIN * @cos(@divFloor(time, SPEED)) + cx;
    const y = SPIN * @sin(@divFloor(time, SPEED)) + cy;

    var r: u16 = 0;
    while (r < mainscreen.h) : (r += 1) {
        var c: u16 = 0;
        while (c < mainscreen.w) : (c += 1) {
            const cell = term.getScreenCell(mainscreen, c, r) orelse break;

            const fc: f32 = @floatFromInt(c);
            const fr: f32 = @floatFromInt(r);

            const dist = @sqrt((fr - x) * (fr - x) + STRETCH * (fc - y) * (fc - y));

            const b: u21 = if (dist < INN_RADIUS) '0' else if (dist < OUT_RADIUS) '.' else ' ';
            cell.symbol = b;
        }
    }
}
