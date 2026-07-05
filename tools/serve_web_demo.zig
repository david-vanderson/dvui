const std = @import("std");
const base64 = std.base64;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = Io.net;
const log = std.log;
const Sha256 = std.crypto.hash.sha2.Sha256;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 4) return error.MissingArguments;
    const addr = comptime net.IpAddress.parse("127.0.0.1", 8080) catch unreachable;

    try readFiles(io, arena, args);

    var server = try addr.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    var io_group: Io.Group = .init;
    defer io_group.cancel(io);

    log.info("View the demo at http://localhost:8080", .{});

    while (true) {
        const stream = server.accept(io) catch |err| {
            log.err("Failed to accept connection: {t}", .{ err });
            continue;
        };
        errdefer stream.close(io);
        try io_group.concurrent(io, accept, .{ stream, io });
    }
}

var html: Response = .{ .mime = "text/html", .location = undefined, .content = undefined, .etag = undefined };
var js: Response = .{ .mime = "text/javascript", .location = undefined, .content = undefined, .etag = undefined };
var wasm: Response = .{ .mime = "application/wasm", .location = undefined, .content = undefined, .etag = undefined };

const not_found: std.http.Status = .not_found;
const not_found_phrase = not_found.phrase().?;

const Response = struct {
    mime: []const u8,
    location: []const u8,
    content: []const u8,
    etag: []const u8,
};

fn responseForLocation(location: []const u8) ?Response {
    const uri = std.Uri.parseAfterScheme("http", location) catch return null;
    var path_buf: [32]u8 = undefined;
    const path = uri.path.toRaw(&path_buf) catch return null;
    return if (path.len == 0 or std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, html.location))
        html
    else if (std.mem.eql(u8, path, js.location))
        js
    else if (std.mem.eql(u8, path, wasm.location))
        wasm
    else
        null;
}

fn readFiles(io: Io, arena: Allocator, args: []const [:0]const u8) !void {
    const cwd: Io.Dir = .cwd();
    var read_buf: [1024]u8 = undefined;
    for (args[1..4], [_]*Response{ &html, &js, &wasm }) |path, response| {
        const file = try cwd.openFile(io, path, .{});
        defer file.close(io);

        response.location = try std.fmt.allocPrint(arena, "/{s}", .{ std.fs.path.basename(path) });

        var file_reader = file.reader(io, &read_buf);
        const reader = &file_reader.interface;
        const content = try reader.allocRemaining(arena, .unlimited);
        response.content = content;

        var hash: [32]u8 = undefined;
        Sha256.hash(content, &hash, .{});
        const etag = try arena.create([2 + base64.url_safe.Encoder.calcSize(hash.len)]u8);
        etag[0] = '"';
        etag[etag.len - 1] = '"';
        _ = base64.url_safe.Encoder.encode(etag[1..etag.len - 1], &hash);
        response.etag = etag;
    }
}

fn accept(stream: net.Stream, io: Io) Io.Cancelable!void {
    acceptInner(stream, io) catch |err| log.err("Connection error: {t}", .{ err });
}

fn acceptInner(stream: net.Stream, io: Io) !void {
    defer stream.close(io);

    var recv_buffer: [1024]u8 = undefined;
    var send_buffer: [1024]u8 = undefined;

    var stream_reader = stream.reader(io, &recv_buffer);
    var stream_writer = stream.writer(io, &send_buffer);
    var server: std.http.Server = .init(&stream_reader.interface, &stream_writer.interface);

    while (server.reader.state == .ready) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => |e| return e,
        };
        try serve(&request);
    }
}

fn serve(request: *std.http.Server.Request) !void {
    if (request.head.method != .GET and request.head.method != .HEAD) {
        request.respond(not_found_phrase, .{ .status = not_found, .keep_alive = false }) catch {};
        return;
    }
    const response = responseForLocation(request.head.target) orelse {
        request.respond(not_found_phrase, .{ .status = not_found, .keep_alive = false }) catch {};
        return;
    };

    var header_iterator = request.iterateHeaders();
    var none_match = true;
    while (header_iterator.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "if-none-match")) {
            none_match = ifNoneMatch(response.etag, header.value);
        }
    }
    if (none_match) {
        try request.respond(response.content, .{
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "etag", .value = response.etag },
                .{ .name = "content-type", .value = response.mime },
                .{ .name = "cross-origin-opener-policy", .value = "same-origin" },
                .{ .name = "cross-origin-embedder-policy", .value = "require-corp" },
            },
        });
    } else {
        try request.respond("", .{
            .keep_alive = false,
            .status = .not_modified,
            .extra_headers = &.{
                .{ .name = "etag", .value = response.etag },
            },
        });
    }
}

fn ifNoneMatch(etag: []const u8, header_value: []const u8) bool {
    var i: usize = 0;
    while (std.mem.findScalarPos(u8, header_value, i, '"')) |start| {
        const end = std.mem.findScalarPos(u8, header_value, start + 1, '"') orelse break;
        if (std.mem.eql(u8, etag, header_value[start..end + 1])) return false;
        if (header_value.len < end + 2 or header_value[end + 2] != ',') break;
        i = end + 2;
    }
    return true;
}
