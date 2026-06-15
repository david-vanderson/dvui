#import <AppKit/AppKit.h>
#import <SDL3/SDL.h>

/* macOS helpers for the SDL3 backend.
 *
 * Scroll-source classifier:
 * SDL3's wheel event doesn't expose `[NSEvent hasPreciseScrollingDeltas]`, and the
 * magnitude-based heuristic in `Window.scrollWheelIndicated` can't reliably tell a
 * classic mouse wheel from a trackpad on macOS — AppKit splits a single wheel click
 * into many momentum-smoothed events, so the per-event delta isn't a stable signal.
 *
 * We install an NSEvent local monitor that runs ahead of SDL's event pump, reads the
 * precision flag verbatim from the NSEvent, and stashes it for the Zig side to query.
 * The handler returns the event unchanged so SDL still sees it. This updates per
 * scroll event, so users who switch between a trackpad and a mouse mid-session get
 * accurate classification on the very next scroll. */

static int g_is_precise = -1;

void dvui_macos_monitor_install(void) {
    static int installed = 0;
    if (installed) return;
    installed = 1;
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel
                                          handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        g_is_precise = [event hasPreciseScrollingDeltas] ? 1 : 0;
        return event;
    }];
}

/* Returns -1 if no scroll event has been seen yet, 0 for classic mouse wheel,
 * 1 for trackpad / Magic Trackpad / Magic Mouse (any precise-deltas source). */
int dvui_macos_monitor_last_scroll_precise(void) {
    return g_is_precise;
}

