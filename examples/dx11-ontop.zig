const std = @import("std");
const dvui = @import("dvui");
const Dx11Backend = @import("Dx11Backend");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();
