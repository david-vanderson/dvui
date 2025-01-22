const std = @import("std");

const Item = struct {
    start: usize, // unicode codepoint
    end: usize, // unicode codepoint (inclusive)
};

const Parser = struct {
    start: usize = 0,
    end: usize = 0,
    alt_mode: bool = false,
    str: []u8,
    parsed: std.ArrayList(Item),

    pub fn commit(this: *@This()) !void {
        if (this.start == this.end) return;
        if (this.alt_mode) {
            this.parsed.items[this.parsed.items.len - 1].end = try std.fmt.parseInt(usize, this.str[this.start..this.end], 16);
        } else {
            const i = try std.fmt.parseInt(usize, this.str[this.start..this.end], 16);
            try this.parsed.append(Item{
                .start = i,
                .end = i,
            });
        }
    }

    pub fn parse(this: *@This()) !void {
        while (this.end < this.str.len) {
            if (std.ascii.isHex(this.str[this.end])) {
                //
            } else if (this.str[this.end] == '-') {
                try this.commit();
                this.alt_mode = true;
                this.start = this.end + 1;
            } else if (this.str[this.end] == ' ') {
                try this.commit();
                this.alt_mode = false;
                this.start = this.end + 1;
            }
            this.end += 1;
        }
        try this.commit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const a = gpa.allocator();
    var p = std.process.Child.init(&.{ "fc-list", ":", "file", "family", "charset" }, a);
    p.stdout_behavior = .Pipe;
    try p.spawn();
    // p.spawnAndWait();
    var buf_reader = std.io.bufferedReader(p.stdout.?.reader());
    const reader = buf_reader.reader();

    while (true) {
        const file = reader.readUntilDelimiterAlloc(a, ':', std.math.maxInt(usize)) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };
        _ = try reader.readByte();
        const name = try reader.readUntilDelimiterAlloc(a, ':', std.math.maxInt(usize));
        try reader.skipBytes(8, .{}); // skip "charset="
        const ranges = try reader.readUntilDelimiterAlloc(a, '\n', std.math.maxInt(usize));
        var parser = Parser{ .str = ranges, .parsed = std.ArrayList(Item).init(a) };
        try parser.parse();
        std.debug.print("{s} {s} {any}\n", .{ file, name, parser.parsed.items });
    }

    _ = try p.wait();
}
