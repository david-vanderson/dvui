#!/bin/sh
# Build an Xcode iOS/iPadOS app (an xcodegen-generated project whose preBuildScript builds
# the Zig static lib -- see examples/ios-example) and run it in a Simulator.
#
# Configurable via env vars so it can drive any dvui-based Xcode project, not just the
# example -- see tools/build-apple/build_apple.zig, which `zig build run-sdl3-ios` uses to
# set these from its RunSimOptions:
#   XCODE_PROJECT_DIR  dir containing the .xcodeproj (default: examples/ios-example/xcode-project)
#   CONFIGURATION       Debug or Release (default: Debug)
#   ZIG_OPTIMIZE        exact `zig build -Doptimize=` value; forwarded to the project's
#                        preBuildScript as an xcodebuild build setting so it doesn't have to
#                        guess ReleaseFast vs ReleaseSafe from CONFIGURATION alone
#   DERIVED_DATA_DIR    xcodebuild -derivedDataPath (default: $XCODE_PROJECT_DIR/build)
#   APP_BUNDLE_OUT      if set, copy the built .app here after building
#   SIMULATOR_DEVICE_FILTER  substring to match when auto-booting a simulator, e.g. "iPad"
#                        (default: iPhone; only used if no simulator is already booted)
set -e

if [ "$(uname)" != "Darwin" ]; then
    echo "error: building/running iOS apps requires macOS + Xcode." >&2
    exit 1
fi
for tool in xcodebuild xcrun; do
    command -v "$tool" >/dev/null 2>&1 || { echo "error: '$tool' not found -- install Xcode (and its command line tools)." >&2; exit 1; }
done

cd "$(dirname "$0")/../.."   # repo root
XCODE_PROJECT_DIR=${XCODE_PROJECT_DIR:-examples/ios-example/xcode-project}
CONFIGURATION=${CONFIGURATION:-Debug}
DERIVED_DATA_DIR=${DERIVED_DATA_DIR:-"$XCODE_PROJECT_DIR/build"}

[ -d "$XCODE_PROJECT_DIR" ] || { echo "error: no such directory: $XCODE_PROJECT_DIR" >&2; exit 1; }
XCODEPROJ=$(find "$XCODE_PROJECT_DIR" -maxdepth 1 -name '*.xcodeproj' | head -1)
if [ -z "$XCODEPROJ" ]; then
    [ -f "$XCODE_PROJECT_DIR/project.yml" ] || { echo "error: no .xcodeproj and no project.yml in $XCODE_PROJECT_DIR" >&2; exit 1; }
    command -v xcodegen >/dev/null 2>&1 || { echo "error: no .xcodeproj found and 'xcodegen' not installed (brew install xcodegen) to generate one from project.yml" >&2; exit 1; }
    echo "No .xcodeproj found in $XCODE_PROJECT_DIR -- generating from project.yml..."
    (cd "$XCODE_PROJECT_DIR" && xcodegen generate)
    XCODEPROJ=$(find "$XCODE_PROJECT_DIR" -maxdepth 1 -name '*.xcodeproj' | head -1)
    [ -n "$XCODEPROJ" ] || { echo "error: xcodegen generate ran but no .xcodeproj appeared in $XCODE_PROJECT_DIR" >&2; exit 1; }
    # recent xcodegen builds always write objectVersion 77 (a format newer than most
    # installed Xcodes support), regardless of the Xcode actually on this machine -- see
    # https://github.com/yonaskolb/XcodeGen/issues/1578. Downgrade to a value every Xcode we
    # care about can read; bump only if a project.yml feature starts requiring a newer format.
    sed -i '' -E 's/(objectVersion = )[0-9]+;/\160;/' "$XCODEPROJ/project.pbxproj"
fi
SCHEME=$(xcodebuild -project "$XCODEPROJ" -list 2>/dev/null | awk '/Schemes:/{f=1;next} f && NF {print $1; exit}')
[ -n "$SCHEME" ] || { echo "error: could not find a scheme in $XCODEPROJ" >&2; exit 1; }

UDID=$(xcrun simctl list devices booted | grep -m1 -Eo '[0-9A-F-]{36}' || true)
if [ -z "$UDID" ]; then
    DEVICE_LINE=$(xcrun simctl list devices available | grep -m1 "${SIMULATOR_DEVICE_FILTER:-iPhone}")
    UDID=$(printf '%s' "$DEVICE_LINE" | grep -Eo '[0-9A-F-]{36}')
    echo "Booting simulator: $DEVICE_LINE"
    xcrun simctl boot "$UDID"
fi
open -a Simulator

ZIG_OPTIMIZE_OVERRIDE=""
[ -n "$ZIG_OPTIMIZE" ] && ZIG_OPTIMIZE_OVERRIDE="ZIG_OPTIMIZE=$ZIG_OPTIMIZE"
xcodebuild -project "$XCODEPROJ" -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" -sdk iphonesimulator -destination "id=$UDID" \
    -derivedDataPath "$DERIVED_DATA_DIR" -quiet build $ZIG_OPTIMIZE_OVERRIDE

APP_PATH=$(find "$DERIVED_DATA_DIR/Build/Products" -maxdepth 2 -name '*.app' | head -1)
[ -n "$APP_PATH" ] || { echo "error: build succeeded but no .app bundle found under $DERIVED_DATA_DIR/Build/Products" >&2; exit 1; }

if [ -n "$APP_BUNDLE_OUT" ]; then
    mkdir -p "$APP_BUNDLE_OUT"
    rm -rf "${APP_BUNDLE_OUT:?}/$(basename "$APP_PATH")"
    cp -R "$APP_PATH" "$APP_BUNDLE_OUT/"
    APP_PATH="$APP_BUNDLE_OUT/$(basename "$APP_PATH")"
fi

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID"
