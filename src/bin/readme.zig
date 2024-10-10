const std = @import("std");
const scu = @import("scured");

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
            .Key => |key| if (key.character.b() == 'q') break,
            else => {},
        }
    }
    // ------------------- End Example ----------------------------------

}
