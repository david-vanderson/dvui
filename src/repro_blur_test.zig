const dvui = @import("dvui.zig");

// Regression test: BlurBackdrop nested inside another floating window (the
// demo window) used to render fully transparent - see BlurBackdrop.zig's
// captureEnd for why.
test "DOCIMG repro nested blur" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 900, .h = 900 } });
    defer t.deinit();

    dvui.Examples.show_demo_window = true;
    dvui.Examples.demo_active = .basic_widgets;

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
            defer box.deinit();
            dvui.Examples.demo(.full);
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try dvui.testing.moveTo("demo_button_blur_backdrop");
    try dvui.testing.click(.left);
    try dvui.testing.settle(frame);

    try t.saveImage(frame, null, "repro-blur.png");
}
