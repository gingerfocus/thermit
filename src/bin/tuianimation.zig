const std = @import("std");
const scu = @import("scured");

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
}

const statbarH = 3;
const sidebarW = 5;

fn fullRedraw(term: *scu.Term, start: i64) !void {
    // line numbers
    const leftside = term.makeScreen(0, 0, sidebarW, term.size[1] - statbarH);

    var r: u16 = 0;
    while (r < leftside.h) : (r += 1) {
        var buf: [4]u8 = .{ ' ', ' ', ' ', '|' };
        const out = try std.fmt.bufPrint(&buf, "{}", .{r});
        std.debug.assert(out.len < 3);

        var c: u16 = 1;
        for (buf) |ch| {
            term.getScreenCell(leftside, c, r).?.setSymbol(ch);
            c += 1;
        }
    }

    const statusbar = term.makeScreen(0, term.size[1] - statbarH, null, statbarH);

    var c: u16 = 0;
    while (c < statusbar.w) : (c += 1) {
        const cell = term.getScreenCell(statusbar, c, 0) orelse break;
        cell.setSymbol('>');
        cell.fg = .Red;
        cell.bg = .Blue;
    }

    term.writeBuffer(statusbar, 3, 1, "footer text");
    term.writeBuffer(statusbar, 6, 2, "animation example");

    try screenRedraw(term, start);
}

fn screenRedraw(term: *scu.Term, start: i64) !void {
    const mainscreen = term.makeScreen(sidebarW, 0, null, term.size[1] - statbarH);

    const now = std.time.milliTimestamp();
    const diff: f64 = @floatFromInt(now - start);

    var r: u16 = 0;
    while (r < mainscreen.h) : (r += 1) {
        var c: u16 = 0;
        while (c < mainscreen.w) : (c += 1) {
            const cell = term.getScreenCell(mainscreen, c, r) orelse break;

            const d: f64 = @floatFromInt(r * 256 + c);
            const d2 = std.math.pow(f64, 1.01, d);
            const cd = @cos(d2);
            const sd = @sin(diff);
            const l = cd + sd;
            const b: u21 = if (l < 0.2) ' ' else if (l < 1.0) '.' else '0';
            cell.setSymbol(b);
        }
    }
}
