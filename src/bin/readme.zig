const std = @import("std");
const trm = @import("thermit");

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;

    // ------------------- Begin Example ----------------------------------
    var term = try trm.Term.init(io, alloc);
    defer term.deinit();

    try term.start(false); // clears the render buffer

    const fullScreen = term.makeScreen(0, 0, null, null);
    term.writeBuffer(fullScreen, 0, 0, "hello world");

    if (term.getCell(0, 1)) |cell| cell.symbol = '本';

    try term.finish(); // flushes the render buffer

    while (true) {
        const ev = try term.tty.read(1000);

        switch (ev) {
            .Key => |key| if (trm.keys.bits(key) == 'q') break,
            else => {},
        }
    }
    // ------------------- End Example ----------------------------------
}
