#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
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

/* True when AppKit considers the window zoomed (green-button maximize). */
int dvui_macos_window_is_zoomed(SDL_Window *window) {
    if (!window) return 0;
    SDL_PropertiesID props = SDL_GetWindowProperties(window);
    NSWindow *ns = (__bridge NSWindow *)SDL_GetPointerProperty(
        props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
    if (!ns) return 0;
    return ns.zoomed ? 1 : 0;
}

/* True when the window is in a native fullscreen Space (menu bar hidden). */
int dvui_macos_window_in_fullscreen_space(SDL_Window *window) {
    if (!window) return 0;
    SDL_PropertiesID props = SDL_GetWindowProperties(window);
    NSWindow *ns = (__bridge NSWindow *)SDL_GetPointerProperty(
        props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
    if (!ns) return 0;
    return (ns.styleMask & NSWindowStyleMaskFullScreen) != 0 ? 1 : 0;
}

/* Prefer native fullscreen Spaces so the menu bar can autohide/reveal on hover. */
void dvui_macos_configure_window(SDL_Window *window) {
    if (!window) return;
    SDL_PropertiesID props = SDL_GetWindowProperties(window);
    NSWindow *ns = (__bridge NSWindow *)SDL_GetPointerProperty(
        props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
    if (!ns) return;
    NSWindowCollectionBehavior behavior = [ns collectionBehavior];
    behavior |= NSWindowCollectionBehaviorFullScreenPrimary;
    [ns setCollectionBehavior:behavior];
}

static NSWindow *cocoa_window(SDL_Window *window) {
    if (!window) return NULL;
    SDL_PropertiesID props = SDL_GetWindowProperties(window);
    return (__bridge NSWindow *)SDL_GetPointerProperty(
        props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
}

/* Launch-time fullscreen restore: AppKit may drop toggleFullScreen until the
 * app is active and the window is visible, so retry with run-loop pumps. */
static int g_launch_space_restore = 0;
static int g_enter_requested = 0;
static double g_enter_request_time = 0;
static int g_enter_attempts = 0;

void dvui_macos_begin_launch_space_restore(void) {
    g_launch_space_restore = 1;
    g_enter_requested = 0;
    g_enter_attempts = 0;
}

void dvui_macos_end_launch_space_restore(void) {
    g_launch_space_restore = 0;
}

void dvui_macos_pump_runloop(void) {
    [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode
                          beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0 / 120.0]];
}

/* Returns 1 when already in a native fullscreen Space, 0 while entering. */
int dvui_macos_enter_fullscreen_space(SDL_Window *window) {
    NSWindow *ns = cocoa_window(window);
    if (!ns) return 0;
    if ((ns.styleMask & NSWindowStyleMaskFullScreen) != 0) {
        g_enter_requested = 0;
        g_enter_attempts = 0;
        return 1;
    }

    double now = CACurrentMediaTime();
    if (g_enter_requested) {
        if (g_launch_space_restore) return 0;
        if ((now - g_enter_request_time) < 0.5) return 0;
    }
    int max_attempts = g_launch_space_restore ? 8 : 4;
    if (g_enter_attempts >= max_attempts) {
        g_enter_requested = 0;
        return 1;
    }
    if (!ns.isVisible && !g_launch_space_restore) return 0;

    [NSApp activateIgnoringOtherApps:YES];
    [ns makeKeyAndOrderFront:nil];
    g_enter_requested = 1;
    g_enter_request_time = now;
    g_enter_attempts++;
    [ns toggleFullScreen:nil];
    return 0;
}
