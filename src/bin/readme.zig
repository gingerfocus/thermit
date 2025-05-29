const std = @import("std");
const scu = @import("scured");
const thr = scu.thermit;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // ------------------- Begin Example ----------------------------------
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
            .Key => |key| if (thr.keys.bits(key) == 'q') break,
            else => {},
        }
    }
    // ------------------- End Example ----------------------------------
}
