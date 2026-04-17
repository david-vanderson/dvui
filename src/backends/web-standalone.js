/// @file web-standalone.js
/// Main-thread script for dvui standalone/Worker mode.
/// Sets up DOM event listeners and forwards events to the Worker
/// via SharedArrayBuffer + Atomics.notify().
/// Falls back to main-thread runtime (web.js) when SAB isolation is unavailable.

const EVENT_RING_OFFSET = 256;
const EVENT_SIZE = 20;
const MAX_EVENTS = 256;
const RING_SIZE = EVENT_SIZE * MAX_EVENTS;
const STRING_AREA_OFFSET = EVENT_RING_OFFSET + RING_SIZE;
const STRING_AREA_SIZE = 4096;
const TOTAL_SHARED_SIZE = STRING_AREA_OFFSET + STRING_AREA_SIZE;

const SIGNAL_INDEX = 0;
const WRITE_CURSOR_INDEX = 1;
const READ_CURSOR_INDEX = 2;
const COLOR_SCHEME_INDEX = 3;
const CANVAS_INFO_OFFSET = 16; // byte offset

const utf8encoder = new TextEncoder();

/**
 * @param {string | HTMLCanvasElement} canvasArg
 * @param {string} wasmUrl
 * @param {string} [workerUrl]
 * @returns {Promise<{worker: Worker, sharedBuffer: SharedArrayBuffer} | unknown>}
 */
export function dvuiStandalone(canvasArg, wasmUrl, workerUrl = "web-worker.js") {
    /** @type {HTMLCanvasElement} */
    const canvas = canvasArg instanceof HTMLCanvasElement
        ? canvasArg
        : document.querySelector(canvasArg);

    if (!canvas) {
        throw new Error("Could not find canvas element: " + canvasArg);
    }

    const search = new URLSearchParams(window.location.search);
    const debugParam = search.get("dvui_debug");
    const probeEnabled = search.get("dvui_probe") === "1";
    const debugEnabled = debugParam === "1";
    if (debugEnabled) {
        console.info("[dvui-standalone] script loaded", {
            debugEnabled,
            probeEnabled,
            href: window.location.href,
        });
    }

    function fallbackToMainThread(reason) {
        console.warn(
            "[dvui-standalone] Falling back to main-thread runtime (web.js):",
            reason
        );
        return import("./web.js").then(({ dvui }) => dvui(canvas, wasmUrl));
    }

    if (typeof SharedArrayBuffer === "undefined") {
        return fallbackToMainThread("SharedArrayBuffer is not available");
    }
    if (typeof Atomics === "undefined") {
        return fallbackToMainThread("Atomics is not available");
    }
    if (!window.crossOriginIsolated) {
        return fallbackToMainThread("crossOriginIsolated is false (missing COOP/COEP)");
    }

    // Create shared memory
    const sharedBuffer = new SharedArrayBuffer(TOTAL_SHARED_SIZE);
    const signalArray = new Int32Array(sharedBuffer);
    const canvasInfoFloat = new Float32Array(sharedBuffer, CANVAS_INFO_OFFSET, 4);

    // String write cursor within the string area (resets each event batch)
    let stringWriteOffset = 0;
    // Transfer canvas to Worker via OffscreenCanvas
    if (typeof canvas.transferControlToOffscreen !== "function") {
        return fallbackToMainThread("OffscreenCanvas transfer is not available");
    }
    const offscreen = canvas.transferControlToOffscreen();

    const worker = new Worker(workerUrl);

    if (debugEnabled) {
        console.debug("[dvui-standalone] debug enabled");
    }

    // Detect color scheme and write to shared buffer
    function updateColorScheme() {
        if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
            Atomics.store(signalArray, COLOR_SCHEME_INDEX, 1);
        } else if (window.matchMedia("(prefers-color-scheme: light)").matches) {
            Atomics.store(signalArray, COLOR_SCHEME_INDEX, 2);
        } else {
            Atomics.store(signalArray, COLOR_SCHEME_INDEX, 0);
        }
    }
    updateColorScheme();
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", updateColorScheme);

    // Update canvas dimensions in shared buffer
    function updateCanvasInfo() {
        const scale = window.devicePixelRatio;
        const w = canvas.clientWidth;
        const h = canvas.clientHeight;
        canvasInfoFloat[0] = Math.round(w * scale); // pixel width
        canvasInfoFloat[1] = Math.round(h * scale); // pixel height
        canvasInfoFloat[2] = w;                       // canvas (CSS) width
        canvasInfoFloat[3] = h;                       // canvas (CSS) height
    }
    updateCanvasInfo();

    /** Write an event into the ring buffer and wake the Worker */
    function pushEvent(kind, int1, int2, float1, float2) {
        const writeCursor = Atomics.load(signalArray, WRITE_CURSOR_INDEX);
        const readCursor = Atomics.load(signalArray, READ_CURSOR_INDEX);

        // Check if ring is full
        if (writeCursor - readCursor >= MAX_EVENTS) {
            console.warn("dvui event ring full, dropping event");
            return;
        }

        const offset = EVENT_RING_OFFSET + (writeCursor % MAX_EVENTS) * EVENT_SIZE;
        const view = new DataView(sharedBuffer, offset, EVENT_SIZE);
        view.setUint8(0, kind);
        view.setUint32(4, int1, true);
        view.setUint32(8, int2, true);
        view.setFloat32(12, float1, true);
        view.setFloat32(16, float2, true);

        Atomics.store(signalArray, WRITE_CURSOR_INDEX, writeCursor + 1);

        // Wake the worker
        Atomics.store(signalArray, SIGNAL_INDEX, 1);
        Atomics.notify(signalArray, SIGNAL_INDEX);
        worker.postMessage({ type: "wake" });
    }

    /** Write a string into the string area and return its offset */
    function pushString(str) {
        const bytes = utf8encoder.encode(str);
        if (stringWriteOffset + bytes.length > STRING_AREA_SIZE) {
            stringWriteOffset = 0; // wrap around (best effort)
        }
        const dest = new Uint8Array(sharedBuffer, STRING_AREA_OFFSET + stringWriteOffset, bytes.length);
        dest.set(bytes);
        const offset = stringWriteOffset;
        stringWriteOffset += bytes.length;
        return [offset, bytes.length];
    }

    /** Push a key event with string data */
    function pushKeyEvent(kind, key, repeat, modifiers) {
        const [strOffset, strLen] = pushString(key);
        pushEvent(kind, strOffset, strLen, repeat ? 1 : 0, modifiers);
    }

    // Touch tracking
    const touches = [];
    function touchIndex(pointerId) {
        let idx = touches.findIndex(e => e[0] === pointerId);
        if (idx < 0) {
            idx = touches.length;
            touches.push([pointerId, idx]);
        }
        return idx;
    }

    // Scroll delta tracking
    const lowestScrollDelta = [99999, 99999];

    // Hidden input for text/IME input
    const hiddenInput = document.createElement("input");
    hiddenInput.setAttribute("autocapitalize", "none");
    hiddenInput.style.position = "absolute";
    hiddenInput.style.left = "0";
    hiddenInput.style.top = "0";
    hiddenInput.style.padding = "0";
    hiddenInput.style.border = "0";
    hiddenInput.style.margin = "0";
    hiddenInput.style.opacity = "0";
    hiddenInput.style.zIndex = "-1";
    document.body.prepend(hiddenInput);

    // Text input rect tracking for OSK
    let textInputRect = [];
    function oskCheck() {
        if (textInputRect.length === 0) {
            canvas.focus();
        } else {
            const rect = canvas.getBoundingClientRect();
            hiddenInput.style.left = (window.scrollX + rect.left + textInputRect[0]) + "px";
            hiddenInput.style.top = (window.scrollY + rect.top + textInputRect[1]) + "px";
            hiddenInput.style.width = Math.max(0, Math.min(textInputRect[2], canvas.clientWidth - textInputRect[0])) + "px";
            hiddenInput.style.height = Math.max(0, Math.min(textInputRect[3], canvas.clientHeight - textInputRect[1])) + "px";
            hiddenInput.focus();
        }
    }

    // ---- Event listeners ----

    canvas.addEventListener("contextmenu", ev => ev.preventDefault());

    window.addEventListener("resize", () => {
        updateCanvasInfo();
        // Wake the worker so it sees the new size
        Atomics.store(signalArray, SIGNAL_INDEX, 1);
        Atomics.notify(signalArray, SIGNAL_INDEX);
        worker.postMessage({ type: "wake" });
    });

    const resizeObserver = new ResizeObserver(() => {
        updateCanvasInfo();
        Atomics.store(signalArray, SIGNAL_INDEX, 1);
        Atomics.notify(signalArray, SIGNAL_INDEX);
        worker.postMessage({ type: "wake" });
    });
    resizeObserver.observe(canvas);

    canvas.addEventListener("mousemove", ev => {
        const rect = canvas.getBoundingClientRect();
        const scale = window.devicePixelRatio;
        const x = (ev.clientX - rect.left) * scale;
        const y = (ev.clientY - rect.top) * scale;
        pushEvent(1, 0, 0, x, y);
    });

    canvas.addEventListener("mousedown", ev => {
        pushEvent(2, ev.button, 0, 0, 0);
    });

    canvas.addEventListener("mouseup", ev => {
        pushEvent(3, ev.button, 0, 0, 0);
    });

    canvas.addEventListener("wheel", ev => {
        ev.preventDefault();
        const touchpadThreshold = 4;
        const touchpadAdj = 0.1;

        if (ev.deltaX !== 0) {
            const min = Math.min(Math.abs(ev.deltaX), lowestScrollDelta[0]);
            lowestScrollDelta[0] = min;
            let ticks = ev.deltaX / min;
            if (min < touchpadThreshold) ticks *= touchpadAdj;
            pushEvent(4, 0, 0, ticks, 0);
        }
        if (ev.deltaY !== 0) {
            const min = Math.min(Math.abs(ev.deltaY), lowestScrollDelta[1]);
            lowestScrollDelta[1] = min;
            let ticks = -ev.deltaY / min;
            if (min < touchpadThreshold) ticks *= touchpadAdj;
            pushEvent(4, 1, 0, ticks, 0);
        }
    }, { passive: false });

    const keydown = ev => {
        if (ev.key === "Tab") {
            if (ev.ctrlKey) return;
            ev.preventDefault();
        }
        if (ev.key.length > 0) {
            const mods = (ev.metaKey << 3) + (ev.altKey << 2) + (ev.ctrlKey << 1) + (ev.shiftKey << 0);
            pushKeyEvent(5, ev.key, ev.repeat, mods);
        }
    };
    canvas.addEventListener("keydown", keydown);
    hiddenInput.addEventListener("keydown", keydown);

    const keyup = ev => {
        const mods = (ev.metaKey << 3) + (ev.altKey << 2) + (ev.ctrlKey << 1) + (ev.shiftKey << 0);
        pushKeyEvent(6, ev.key, false, mods);
    };
    canvas.addEventListener("keyup", keyup);
    hiddenInput.addEventListener("keyup", keyup);

    hiddenInput.addEventListener("beforeinput", ev => {
        ev.preventDefault();
        if (ev.data && !ev.isComposing) {
            const [strOffset, strLen] = pushString(ev.data);
            pushEvent(7, strOffset, strLen, 0, 0);
        }
    });
    hiddenInput.addEventListener("compositionend", ev => {
        if (ev.data) {
            const [strOffset, strLen] = pushString(ev.data);
            pushEvent(7, strOffset, strLen, 0, 0);
        }
        ev.target.value = "";
    });

    canvas.addEventListener("touchstart", ev => {
        ev.preventDefault();
        const rect = canvas.getBoundingClientRect();
        for (let i = 0; i < ev.changedTouches.length; i++) {
            const touch = ev.changedTouches[i];
            const x = (touch.clientX - rect.left) / (rect.right - rect.left);
            const y = (touch.clientY - rect.top) / (rect.bottom - rect.top);
            const tidx = touchIndex(touch.identifier);
            pushEvent(8, touches[tidx][1], 0, x, y);
        }
    });
    canvas.addEventListener("touchend", ev => {
        ev.preventDefault();
        const rect = canvas.getBoundingClientRect();
        for (let i = 0; i < ev.changedTouches.length; i++) {
            const touch = ev.changedTouches[i];
            const x = (touch.clientX - rect.left) / (rect.right - rect.left);
            const y = (touch.clientY - rect.top) / (rect.bottom - rect.top);
            const tidx = touchIndex(touch.identifier);
            pushEvent(9, touches[tidx][1], 0, x, y);
            touches.splice(tidx, 1);
        }
        oskCheck();
    });
    canvas.addEventListener("touchmove", ev => {
        ev.preventDefault();
        const rect = canvas.getBoundingClientRect();
        for (let i = 0; i < ev.changedTouches.length; i++) {
            const touch = ev.changedTouches[i];
            const x = (touch.clientX - rect.left) / (rect.right - rect.left);
            const y = (touch.clientY - rect.top) / (rect.bottom - rect.top);
            const tidx = touchIndex(touch.identifier);
            pushEvent(10, touches[tidx][1], 0, x, y);
        }
    });

    // Handle messages from Worker
    worker.onmessage = function(e) {
        const msg = e.data;
        switch (msg.type) {
            case "cursor":
                canvas.style.cursor = msg.cursor;
                break;
            case "text_input":
                if (msg.rect[2] > 0 && msg.rect[3] > 0) {
                    textInputRect = msg.rect;
                } else {
                    textInputRect = [];
                }
                break;
            case "open_url":
                if (msg.new_window) {
                    window.open(msg.url);
                } else {
                    window.location.href = msg.url;
                }
                break;
            case "download": {
                const blob = new Blob([msg.data], { type: "application/octet-stream" });
                const url = URL.createObjectURL(blob);
                const a = document.createElement("a");
                a.href = url;
                a.download = msg.name;
                a.click();
                a.remove();
                URL.revokeObjectURL(url);
                break;
            }
            case "clipboard_set":
                if (navigator.clipboard) {
                    navigator.clipboard.writeText(msg.text);
                }
                break;
            case "panic":
                console.error("WASM Panic:", msg.message);
                alert(msg.message);
                break;
            case "error":
                console.error("Worker error:", msg.message);
                break;
            case "ready":
                console.log("dvui worker ready");
                break;
            case "debug":
                console.log("[dvui-worker]", msg.message, msg.data ?? "");
                break;
        }
    };

    // Send init message to worker with OffscreenCanvas
    worker.postMessage({
        type: "init",
        canvas: offscreen,
        sharedBuffer: sharedBuffer,
        wasmUrl: wasmUrl,
        platform: navigator.platform || "",
        debug: debugEnabled,
        probe: probeEnabled,
    }, [offscreen]);
    if (debugEnabled) {
        console.info("[dvui-standalone] init posted to worker", { debugEnabled, probeEnabled, wasmUrl, workerUrl });
    }

    return Promise.resolve({ worker, sharedBuffer });
}
