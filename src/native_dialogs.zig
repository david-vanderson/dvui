pub const Wasm = struct {
    pub const DialogOptions = struct {
        /// Filter files shown by setting the [accept](https://developer.mozilla.org/en-US/docs/Web/HTML/Attributes/accept) attribute
        ///
        /// Example: ".pdf, image/*"
        accept: ?[]const u8 = null,
    };

    const File = struct {
        id: dvui.Id,
        index: usize,
        /// The size of the data in bytes
        size: usize,
        /// The filename of the uploaded file. Does not include the path of the file
        name: [:0]const u8,

        pub fn readData(self: *File, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
            std.debug.assert(dvui.wasm); // WasmFile shouldn't be used outside wasm builds
            const data = try allocator.alloc(u8, self.size);
            dvui.backend.readFileData(self.id, self.index, data.ptr);
            return data;
        }
    };

    /// Opens a file picker WITHOUT blocking. The file can be accessed by calling `wasmFileUploaded` with the same id
    ///
    /// This function does nothing in non-wasm builds
    pub fn open(id: dvui.Id, opts: DialogOptions) void {
        if (comptime !dvui.wasm) return;
        dvui.backend.openFilePicker(id, opts.accept, false);
    }

    /// Will only return a non-null value for a single frame
    ///
    /// This function does nothing in non-wasm builds
    pub fn uploaded(id: dvui.Id) ?File {
        if (comptime !dvui.wasm) return null;
        const num_files = dvui.backend.getNumberOfFilesAvailable(id);
        if (num_files == 0) return null;
        if (num_files > 1) {
            dvui.log.err("Received more than one file for id {d}. Did you mean to call wasmFileUploadedMultiple?", .{id});
        }
        const name = dvui.backend.getFileName(id, 0);
        const size = dvui.backend.getFileSize(id, 0);
        if (name == null or size == null) {
            dvui.log.err("Could not get file metadata. Got size: {?d} and name: {?s}", .{ size, name });
            return null;
        }
        return .{
            .id = id,
            .index = 0,
            .size = size.?,
            .name = name.?,
        };
    }

    /// Opens a file picker WITHOUT blocking. The files can be accessed by calling `wasmFileUploadedMultiple` with the same id
    ///
    /// This function does nothing in non-wasm builds
    pub fn openMultiple(id: dvui.Id, opts: DialogOptions) void {
        if (comptime !dvui.wasm) return;
        dvui.backend.openFilePicker(id, opts.accept, true);
    }

    /// Will only return a non-null value for a single frame
    ///
    /// This function does nothing in non-wasm builds
    pub fn uploadedMultiple(id: dvui.Id) ?[]File {
        if (comptime !dvui.wasm) return null;
        const num_files = dvui.backend.getNumberOfFilesAvailable(id);
        if (num_files == 0) return null;

        const files = dvui.currentWindow().arena().alloc(File, num_files) catch |err| {
            dvui.log.err("File upload skipped, failed to allocate space for file handles: {any}", .{err});
            return null;
        };
        for (0.., files) |i, *file| {
            const name = dvui.backend.getFileName(id, i);
            const size = dvui.backend.getFileSize(id, i);
            if (name == null or size == null) {
                dvui.log.err("Could not get file metadata for id {d} file number {d}. Got size: {?d} and name: {?s}", .{ id, i, size, name });
                return null;
            }
            file.* = .{
                .id = id,
                .index = i,
                .size = size.?,
                .name = name.?,
            };
        }
        return files;
    }
};

pub const Native = struct {
    pub const DialogOptions = struct {
        /// Title of the dialog window
        title: ?[]const u8 = null,

        /// Starting file or directory (if ends with /)
        path: ?[]const u8 = null,

        /// Filter files shown .filters = .{"*.png", "*.jpg"}
        filters: ?[]const []const u8 = null,

        /// Description for filters given ("image files")
        filter_description: ?[]const u8 = null,
    };

    /// Block while showing a native file open dialog.  Return the selected file
    /// path or null if cancelled.  See `dialogNativeFileOpenMultiple`
    ///
    /// Not thread safe, but can be used from any thread.
    ///
    /// Returned string is created by passed allocator.  Not implemented for web (returns null).
    pub fn open(alloc: std.mem.Allocator, opts: DialogOptions) std.mem.Allocator.Error!?[:0]const u8 {
        return internal(.open, alloc, opts);
    }

    /// Block while showing a native file open dialog with multiple selection.
    /// Return the selected file paths or null if cancelled.
    ///
    /// Not thread safe, but can be used from any thread.
    ///
    /// Returned slice and strings are created by passed allocator.  Not implemented for web (returns null).
    pub fn openMultiple(alloc: std.mem.Allocator, opts: DialogOptions) std.mem.Allocator.Error!?[][:0]const u8 {
        return internal(.openMultiple, alloc, opts);
    }

    /// Block while showing a native file save dialog.  Return the selected file
    /// path or null if cancelled.
    ///
    /// Not thread safe, but can be used from any thread.
    ///
    /// Returned string is created by passed allocator.  Not implemented for web (returns null).
    pub fn save(alloc: std.mem.Allocator, opts: DialogOptions) std.mem.Allocator.Error!?[:0]const u8 {
        return internal(.save, alloc, opts);
    }

    const InternalKind = enum { save, open, openMultiple };
    fn internal(comptime kind: InternalKind, alloc: std.mem.Allocator, opts: DialogOptions) if (kind == .openMultiple) std.mem.Allocator.Error!?[][:0]const u8 else std.mem.Allocator.Error!?[:0]const u8 {
        var backing: [500]u8 = undefined;
        var buf: []u8 = &backing;

        var title: ?[*:0]const u8 = null;
        if (opts.title) |t| {
            const dupe = std.fmt.bufPrintZ(buf, "{s}", .{t}) catch null;
            if (dupe) |dt| {
                title = dt.ptr;
                buf = buf[dt.len + 1 ..];
            }
        }

        var path: ?[*:0]const u8 = null;
        if (opts.path) |p| {
            const dupe = std.fmt.bufPrintZ(buf, "{s}", .{p}) catch null;
            if (dupe) |dp| {
                path = dp.ptr;
                buf = buf[dp.len + 1 ..];
            }
        }

        var filters_backing: [20:null]?[*:0]const u8 = undefined;
        var filters: ?[*:null]?[*:0]const u8 = null;
        var filter_count: usize = 0;
        if (opts.filters) |fs| {
            filters = &filters_backing;
            for (fs, 0..) |f, i| {
                if (i == filters_backing.len) {
                    dvui.log.err("dialogNativeFileOpen got too many filters {d}, only using {d}", .{ fs.len, filters_backing.len });
                    break;
                }
                const dupe = std.fmt.bufPrintZ(buf, "{s}", .{f}) catch null;
                if (dupe) |df| {
                    filters.?[i] = df;
                    filters.?[i + 1] = null;
                    filter_count = i + 1;
                    buf = buf[df.len + 1 ..];
                }
            }
        }

        var filter_desc: ?[*:0]const u8 = null;
        if (opts.filter_description) |fd| {
            const dupe = std.fmt.bufPrintZ(buf, "{s}", .{fd}) catch null;
            if (dupe) |dfd| {
                filter_desc = dfd.ptr;
                buf = buf[dfd.len + 1 ..];
            }
        }

        var result: if (kind == .openMultiple) ?[][:0]const u8 else ?[:0]const u8 = null;
        const tfd_ret: [*c]const u8 = switch (kind) {
            .open, .openMultiple => dvui.c.tinyfd_openFileDialog(title, path, @intCast(filter_count), filters, filter_desc, if (kind == .openMultiple) 1 else 0),
            .save => dvui.c.tinyfd_saveFileDialog(title, path, @intCast(filter_count), filters, filter_desc),
        };

        if (tfd_ret) |r| {
            if (kind == .openMultiple) {
                const r_slice = std.mem.span(r);
                const num = std.mem.count(u8, r_slice, "|") + 1;
                result = try alloc.alloc([:0]const u8, num);
                var it = std.mem.splitScalar(u8, r_slice, '|');
                var i: usize = 0;
                while (it.next()) |f| {
                    result.?[i] = try alloc.dupeZ(u8, f);
                    i += 1;
                }
            } else {
                result = try alloc.dupeZ(u8, std.mem.span(r));
            }
        }

        // TODO: tinyfd maintains malloced memory from call to call, and we should
        // figure out a way to get it to release that.

        return result;
    }

    pub const FolderDialogOptions = struct {
        /// Title of the dialog window
        title: ?[]const u8 = null,

        /// Starting file or directory (if ends with /)
        path: ?[]const u8 = null,
    };

    /// Block while showing a native folder select dialog. Return the selected
    /// folder path or null if cancelled.
    ///
    /// Not thread safe, but can be used from any thread.
    ///
    /// Returned string is created by passed allocator.  Not implemented for web (returns null).
    pub fn folderSelect(alloc: std.mem.Allocator, opts: FolderDialogOptions) std.mem.Allocator.Error!?[]const u8 {
        var backing: [500]u8 = undefined;
        var buf: []u8 = &backing;

        var title: ?[*:0]const u8 = null;
        if (opts.title) |t| {
            const dupe = std.fmt.bufPrintZ(buf, "{s}", .{t}) catch null;
            if (dupe) |dt| {
                title = dt.ptr;
                buf = buf[dt.len + 1 ..];
            }
        }

        var path: ?[*:0]const u8 = null;
        if (opts.path) |p| {
            const dupe = std.fmt.bufPrintZ(buf, "{s}", .{p}) catch null;
            if (dupe) |dp| {
                path = dp.ptr;
                buf = buf[dp.len + 1 ..];
            }
        }

        var result: ?[]const u8 = null;
        const tfd_ret = dvui.c.tinyfd_selectFolderDialog(title, path);
        if (tfd_ret) |r| {
            result = try alloc.dupe(u8, std.mem.sliceTo(r, 0));
        }

        // TODO: tinyfd maintains malloced memory from call to call, and we should
        // figure out a way to get it to release that.

        return result;
    }
};

const std = @import("std");
const dvui = @import("dvui.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
