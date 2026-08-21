const std = @import("std");

pub const RunSimOptions = struct {
    /// Dir (relative to the invoking build's root) containing the .xcodeproj to build/run.
    /// Callers set this explicitly -- e.g. a different value per Xcode project if a
    /// downstream project keeps more than one.
    xcode_project_dir: []const u8,
    /// Where xcodebuild puts build products (-derivedDataPath). Defaults to
    /// `<xcode_project_dir>/build`; callers set this explicitly if they want build output
    /// somewhere else (e.g. shared across multiple Xcode projects).
    derived_data_dir: ?[]const u8 = null,
    /// Drives both the Xcode Debug/Release configuration and the exact zig
    /// `-Doptimize=` value the project's preBuildScript uses for its `zig build lib` --
    /// single source of truth (usually `b.standardOptimizeOption(.{})`), not a separate flag.
    optimize: std.builtin.OptimizeMode,
    /// If set, copy the built .app bundle here after building.
    app_bundle_out: ?[]const u8 = null,
    /// Substring to match when auto-booting a simulator if none is already booted
    /// (default "iPhone" in run-sim.sh). Set to "iPad" etc. to prefer a different device.
    simulator_device_filter: ?[]const u8 = null,
};

/// Adds a step that builds `opts.xcode_project_dir`'s Xcode project and runs it in an iOS/
/// iPadOS Simulator via tools/build-apple/run-sim.sh. macOS host only -- callers should gate
/// this behind `builtin.os.tag == .macos`.
pub fn addRunSimStep(b: *std.Build, name: []const u8, description: []const u8, opts: RunSimOptions) *std.Build.Step {
    const run = b.addSystemCommand(&.{ "sh", "tools/build-apple/run-sim.sh" });
    run.setEnvironmentVariable("XCODE_PROJECT_DIR", opts.xcode_project_dir);
    run.setEnvironmentVariable("CONFIGURATION", if (opts.optimize == .Debug) "Debug" else "Release");
    run.setEnvironmentVariable("ZIG_OPTIMIZE", @tagName(opts.optimize));
    if (opts.derived_data_dir) |dir| run.setEnvironmentVariable("DERIVED_DATA_DIR", dir);
    if (opts.app_bundle_out) |dir| run.setEnvironmentVariable("APP_BUNDLE_OUT", dir);
    if (opts.simulator_device_filter) |filter| run.setEnvironmentVariable("SIMULATOR_DEVICE_FILTER", filter);

    const step = b.step(name, description);
    step.dependOn(&run.step);
    return step;
}
