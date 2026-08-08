const std = @import("std");

const empty_field: []const u8 = "";

const Dimensions = struct {
    num_rows: usize,
    num_cols: usize,
};

pub const Table = struct {
    src: []const u8,
    cells: []const []const u8,
    num_rows: usize,
    num_cols: usize,

    pub fn cell(self: Table, row: usize, col: usize) []const u8 {
        return self.cells[row * self.num_cols + col];
    }
};

/// Unescape a quoted field in place within `[open_quote..close_quote)` only.
/// Does not move bytes after `close_quote`, so the rest of the buffer is unchanged.
fn finishQuotedField(src: []u8, open_quote: usize, close_quote: usize) []const u8 {
    var write: usize = open_quote + 1;
    var read: usize = open_quote + 1;
    while (read < close_quote) : (read += 1) {
        if (src[read] == '"' and read + 1 < close_quote and src[read + 1] == '"') {
            src[write] = '"';
            write += 1;
            read += 1;
        } else {
            src[write] = src[read];
            write += 1;
        }
    }
    return src[open_quote + 1 .. write];
}

const Parser = struct {
    src: []u8,
    cells: ?[]const []const u8,
    dim: Dimensions,
    i: usize = 0,
    in_quotes: bool = false,
    field_start: usize = 0,
    row: usize = 0,
    col: usize = 0,
    row_cols: usize = 0,
    last_row_single_empty: bool = false,
    last_field_empty: bool = false,
    skip_trailing_empty_row: bool = false,

    fn flushField(self: *Parser, end: usize) void {
        const value: []const u8 = if (self.in_quotes)
            finishQuotedField(self.src, self.field_start, end)
        else
            self.src[self.field_start..end];

        if (self.cells) |grid| {
            if (self.row >= self.dim.num_rows) return;
            const cells = @constCast(grid);
            cells[self.row * self.dim.num_cols + self.col] = value;
            self.col += 1;
        } else {
            self.last_field_empty = value.len == 0;
            self.row_cols += 1;
        }
        self.in_quotes = false;
    }

    fn flushRow(self: *Parser) void {
        if (self.cells) |grid| {
            if (self.row >= self.dim.num_rows) return;
            const cells = @constCast(grid);
            while (self.col < self.dim.num_cols) {
                cells[self.row * self.dim.num_cols + self.col] = empty_field;
                self.col += 1;
            }
            self.row += 1;
            self.col = 0;
        } else if (self.row_cols > 0) {
            self.last_row_single_empty = self.row_cols == 1 and self.last_field_empty;
            self.dim.num_rows += 1;
            self.dim.num_cols = @max(self.dim.num_cols, self.row_cols);
            self.row_cols = 0;
        }
    }

    fn run(self: *Parser) void {
        while (self.i < self.src.len) {
            const c = self.src[self.i];
            if (self.in_quotes) {
                if (c == '"') {
                    if (self.i + 1 < self.src.len and self.src[self.i + 1] == '"') {
                        self.i += 2;
                    } else {
                        if (self.cells != null) {
                            self.flushField(self.i);
                            self.i += 1;
                            self.field_start = self.i;
                        } else {
                            self.last_field_empty = false;
                            self.row_cols += 1;
                            self.in_quotes = false;
                            self.i += 1;
                            self.field_start = self.i;
                        }
                    }
                } else {
                    self.i += 1;
                }
                continue;
            }
            switch (c) {
                '"' => {
                    self.in_quotes = true;
                    self.field_start = self.i;
                    self.i += 1;
                },
                ',' => {
                    if (self.field_start < self.i) self.flushField(self.i);
                    self.i += 1;
                    self.field_start = self.i;
                },
                '\n' => {
                    self.flushField(self.i);
                    self.i += 1;
                    self.flushRow();
                    self.field_start = self.i;
                },
                '\r' => {
                    self.flushField(self.i);
                    self.i += 1;
                    if (self.i < self.src.len and self.src[self.i] == '\n') self.i += 1;
                    self.flushRow();
                    self.field_start = self.i;
                },
                else => self.i += 1,
            }
        }

        if (self.skip_trailing_empty_row and self.cells != null) return;

        if (self.field_start < self.i or self.in_quotes) {
            self.flushField(self.i);
        }
        self.flushRow();
    }
};

fn dropTrailingEmptyRow(counter: *const Parser, dim: *Dimensions) void {
    if (dim.num_rows > 0 and counter.last_row_single_empty) {
        dim.num_rows -= 1;
    }
}

pub fn parse(allocator: std.mem.Allocator, src: []u8) !Table {
    var counter: Parser = .{
        .src = src,
        .cells = null,
        .dim = .{ .num_rows = 0, .num_cols = 0 },
    };
    counter.run();
    var dim = counter.dim;
    dropTrailingEmptyRow(&counter, &dim);

    const cells = try allocator.alloc([]const u8, dim.num_rows * dim.num_cols);
    errdefer allocator.free(cells);
    @memset(cells, empty_field);

    if (dim.num_rows > 0 and dim.num_cols > 0) {
        var filler: Parser = .{
            .src = src,
            .cells = cells,
            .dim = dim,
            .skip_trailing_empty_row = counter.last_row_single_empty,
        };
        filler.run();
    }

    return .{
        .src = src,
        .cells = cells,
        .num_rows = dim.num_rows,
        .num_cols = dim.num_cols,
    };
}

pub const SortDirection = enum {
    ascending,
    descending,
};

fn rowLess(table: *const Table, base: usize, col: usize, desc: bool, a: usize, b: usize) bool {
    const ord = std.mem.order(u8, table.cell(base + a, col), table.cell(base + b, col));
    return if (desc) ord == .gt else ord == .lt;
}

fn rowSwap(table: *Table, base: usize, a: usize, b: usize) void {
    const nc = table.num_cols;
    const cells = @constCast(table.cells);
    const off_a = (base + a) * nc;
    const off_b = (base + b) * nc;
    for (0..nc) |c| {
        const tmp = cells[off_a + c];
        cells[off_a + c] = cells[off_b + c];
        cells[off_b + c] = tmp;
    }
}

/// Reorder data rows in place (rows `data_start_row..`). Header row is not moved.
pub fn sortDataRows(
    table: *Table,
    data_start_row: usize,
    col: usize,
    dir: SortDirection,
) void {
    const data_count = if (data_start_row < table.num_rows) table.num_rows - data_start_row else 0;
    if (data_count <= 1 or col >= table.num_cols) return;

    const desc = dir == .descending;
    var i: usize = 0;
    while (i < data_count) : (i += 1) {
        var j: usize = i + 1;
        while (j < data_count) : (j += 1) {
            if (rowLess(table, data_start_row, col, desc, j, i)) {
                rowSwap(table, data_start_row, i, j);
            }
        }
    }
}

pub fn freeTable(allocator: std.mem.Allocator, table: Table) void {
    allocator.free(table.cells);
}

fn fieldNeedsQuotes(field: []const u8) bool {
    for (field) |c| {
        switch (c) {
            ',', '"', '\n', '\r' => return true,
            else => {},
        }
    }
    return false;
}

fn writeField(writer: anytype, field: []const u8) !void {
    if (!fieldNeedsQuotes(field)) {
        try writer.writeAll(field);
        return;
    }
    try writer.writeByte('"');
    for (field) |c| {
        if (c == '"') {
            try writer.writeAll("\"\"");
        } else {
            try writer.writeByte(c);
        }
    }
    try writer.writeByte('"');
}

pub fn serialize(allocator: std.mem.Allocator, table: Table) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(allocator);
    defer allocator.free(aw.writer.buffer);

    for (0..table.num_rows) |row| {
        for (0..table.num_cols) |col| {
            if (col > 0) try aw.writer.writeByte(',');
            try writeField(&aw.writer, table.cell(row, col));
        }
        if (row + 1 < table.num_rows) try aw.writer.writeByte('\n');
    }

    return try allocator.dupe(u8, aw.writer.buffer[0..aw.writer.end]);
}

fn parseBuf(allocator: std.mem.Allocator, input: []const u8) !struct { Table, []u8 } {
    const buf = try allocator.dupe(u8, input);
    const table = try parse(allocator, buf);
    return .{ table, buf };
}

test "simple csv" {
    const a = std.testing.allocator;
    const parsed = try parseBuf(a, "a,b,c\n1,2,3");
    defer a.free(parsed[1]);
    defer freeTable(a, parsed[0]);
    const table = parsed[0];
    try std.testing.expectEqual(@as(usize, 2), table.num_rows);
    try std.testing.expectEqual(@as(usize, 3), table.num_cols);
    try std.testing.expectEqualStrings("a", table.cell(0, 0));
    try std.testing.expectEqualStrings("3", table.cell(1, 2));
}

test "quoted comma" {
    const a = std.testing.allocator;
    const parsed = try parseBuf(a, "name,value\n\"foo,bar\",1");
    defer a.free(parsed[1]);
    defer freeTable(a, parsed[0]);
    const table = parsed[0];
    try std.testing.expectEqualStrings("foo,bar", table.cell(1, 0));
    try std.testing.expectEqualStrings("1", table.cell(1, 1));
}

test "escaped quotes" {
    const a = std.testing.allocator;
    const parsed = try parseBuf(a, "\"a\"\"b\"");
    defer a.free(parsed[1]);
    defer freeTable(a, parsed[0]);
    const table = parsed[0];
    try std.testing.expectEqualStrings("a\"b", table.cell(0, 0));
}

test "ragged rows padded" {
    const a = std.testing.allocator;
    const parsed = try parseBuf(a, "a,b\n1");
    defer a.free(parsed[1]);
    defer freeTable(a, parsed[0]);
    const table = parsed[0];
    try std.testing.expectEqual(@as(usize, 2), table.num_cols);
    try std.testing.expectEqualStrings("", table.cell(1, 1));
}

test "sort data rows" {
    const a = std.testing.allocator;
    const parsed = try parseBuf(a, "h1,h2\nb,2\na,1\nc,3");
    defer a.free(parsed[1]);
    defer freeTable(a, parsed[0]);
    var table = parsed[0];
    sortDataRows(&table, 1, 0, .ascending);
    try std.testing.expectEqualStrings("a", table.cell(1, 0));
    try std.testing.expectEqualStrings("b", table.cell(2, 0));
    try std.testing.expectEqualStrings("c", table.cell(3, 0));
    try std.testing.expectEqualStrings("h1", table.cell(0, 0));
    sortDataRows(&table, 1, 1, .descending);
    try std.testing.expectEqualStrings("3", table.cell(1, 1));
    try std.testing.expectEqualStrings("2", table.cell(2, 1));
    try std.testing.expectEqualStrings("1", table.cell(3, 1));
}

test "round trip" {
    const a = std.testing.allocator;
    const parsed = try parseBuf(a, "h1,h2\n\"x,y\",z\n");
    defer a.free(parsed[1]);
    defer freeTable(a, parsed[0]);
    const table = parsed[0];
    const out = try serialize(a, table);
    defer a.free(out);
    const out_owned = try a.dupe(u8, out);
    defer a.free(out_owned);
    const table2 = try parse(a, out_owned);
    defer freeTable(a, table2);
    try std.testing.expectEqual(table.num_rows, table2.num_rows);
    try std.testing.expectEqual(table.num_cols, table2.num_cols);
    for (table.cells, table2.cells) |a_cell, b_cell| {
        try std.testing.expectEqualStrings(a_cell, b_cell);
    }
}

test "large csv one quoted field" {
    const a = std.testing.allocator;
    var data = std.ArrayList(u8).empty;
    defer data.deinit(a);
    try data.appendSlice(a, "id,name,email,score,active\n");
    var row: [128]u8 = undefined;
    for (1..42) |n| {
        const line = try std.fmt.bufPrint(&row, "{d},User {d},user{d}@example.com,{d}.1,false\n", .{ n, n, n, n });
        try data.appendSlice(a, line);
    }
    try data.appendSlice(a, "42,\"User, Jr.\",user42@example.com,42.2,true\n");
    for (43..1001) |n| {
        const line = try std.fmt.bufPrint(&row, "{d},User {d},user{d}@example.com,{d}.1,false\n", .{ n, n, n, n });
        try data.appendSlice(a, line);
    }

    const buf = try a.dupe(u8, data.items);
    defer a.free(buf);
    const header_snapshot = try a.dupe(u8, buf[0..30]);
    defer a.free(header_snapshot);

    const table = try parse(a, buf);
    defer freeTable(a, table);

    try std.testing.expectEqual(@as(usize, 1001), table.num_rows);
    try std.testing.expectEqual(@as(usize, 5), table.num_cols);
    try std.testing.expectEqualStrings("User, Jr.", table.cell(42, 1));
    try std.testing.expectEqualStrings(header_snapshot, buf[0..30]);
}
