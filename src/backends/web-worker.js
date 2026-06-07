/// @file web-worker.js
/// Worker-side script for dvui standalone mode.
/// Runs WASM in a Web Worker with OffscreenCanvas for WebGL rendering.
/// Events arrive via SharedArrayBuffer from the main thread.
///

import {
    WebRenderer,
    vertexShaderSource_webgl2,
    vertexShaderSource_webgl,
    fragmentShaderSource_webgl2,
    fragmentShaderSource_webgl,
    SIGNAL_INDEX,
    WRITE_CURSOR_INDEX,
    READ_CURSOR_INDEX,
    COLOR_SCHEME_INDEX,
    CANVAS_INFO_OFFSET,
    EVENT_RING_OFFSET,
    EVENT_SIZE,
    MAX_EVENTS,
    STRING_AREA_OFFSET,
    STRING_AREA_SIZE,
} from "./web-common.js";

class WorkerRenderer extends WebRenderer {
    /** @type {OffscreenCanvas | null} */
    canvas = null;
    /** @type {SharedArrayBuffer | null} */
    sharedBuffer = null;
    /** @type {Int32Array | null} */
    signalArray = null;
    /** @type {Float32Array | null} */
    canvasInfoFloat = null;

    cachedPixelWidth = 800;
    cachedPixelHeight = 600;
    cachedCanvasWidth = 800;
    cachedCanvasHeight = 600;

    debugEnabled = false;
    debugWaitCalls = 0;
    debugDrawCalls = 0;
    debugEventsDrained = 0;
    startupTraceCount = 0;

    constructor() {
        super();
        this.imports = { dvui: this.buildImports() };
    }

    debugLog(message, data = null) {
        if (!this.debugEnabled) return;
        if (data === null) {
            self.postMessage({ type: "debug", message });
        } else {
            self.postMessage({ type: "debug", message, data });
        }
    }

    syncCanvasSize(pixelWidth, pixelHeight) {
        if (!(pixelWidth > 0 && pixelHeight > 0)) return false;
        if (this.gl.canvas.width === pixelWidth && this.gl.canvas.height === pixelHeight) return false;

        this.gl.canvas.width = pixelWidth;
        this.gl.canvas.height = pixelHeight;
        this.renderTargetSize = [pixelWidth, pixelHeight];
        this.gl.viewport(0, 0, pixelWidth, pixelHeight);
        this.gl.scissor(0, 0, pixelWidth, pixelHeight);

        this.gl.enable(this.gl.BLEND);
        this.gl.blendFunc(this.gl.ONE, this.gl.ONE_MINUS_SRC_ALPHA);
        this.gl.enable(this.gl.SCISSOR_TEST);
        return true;
    }

    updateCanvasInfo() {
        this.cachedPixelWidth = this.canvasInfoFloat[0];
        this.cachedPixelHeight = this.canvasInfoFloat[1];
        this.cachedCanvasWidth = this.canvasInfoFloat[2];
        this.cachedCanvasHeight = this.canvasInfoFloat[3];
    }

    drainEvents() {
        const writeCursor = Atomics.load(this.signalArray, WRITE_CURSOR_INDEX);
        let readCursor = Atomics.load(this.signalArray, READ_CURSOR_INDEX);
        let drained = 0;

        while (readCursor !== writeCursor) {
            const offset = EVENT_RING_OFFSET + (readCursor & (MAX_EVENTS - 1)) * EVENT_SIZE;
            const view = new DataView(this.sharedBuffer, offset, EVENT_SIZE);
            const kind = view.getUint8(0);
            const int1 = view.getUint32(4, true);
            const int2 = view.getUint32(8, true);
            const float1 = view.getFloat32(12, true);
            const float2 = view.getFloat32(16, true);

            if (kind === 5 || kind === 6 || kind === 7) {
                // Key/text strings live in the shared string area; int1 = offset, int2 = length.
                const strOffset = int1;
                const strLen = int2;
                if (strLen > 0 && strLen < 256) {
                    const strBytes = new Uint8Array(this.sharedBuffer, STRING_AREA_OFFSET + strOffset, strLen);
                    const ptr = this.allocBuffer(this.instance.exports.arena_u8, strBytes);
                    this.instance.exports.add_event(kind, ptr, strLen, float1, float2);
                }
            } else {
                this.instance.exports.add_event(kind, int1, int2, float1, float2);
            }

            readCursor++;
            Atomics.store(this.signalArray, READ_CURSOR_INDEX, readCursor);
            drained++;
            this.debugEventsDrained++;
        }

        return drained;
    }

    setupWebGL(canvas) {
        const program = super.setupWebGL(canvas);
        if (this.gl) {
            this.debugLog("setupWebGL", {
                context: this.webgl2 ? "webgl2" : "webgl1",
                version: this.gl.getParameter(this.gl.VERSION),
                renderer: this.gl.getParameter(this.gl.RENDERER),
                hasCommit: typeof this.gl.commit === "function",
            });
        }
        return program;
    }

    async init(msg) {
        this.debugEnabled = !!msg.debug;
        this.debugLog("worker init received", {
            debugEnabled: this.debugEnabled,
            wasmUrlType: typeof msg.wasmUrl,
            hasSharedBuffer: !!msg.sharedBuffer,
        });

        this.sharedBuffer = msg.sharedBuffer;
        this.signalArray = new Int32Array(this.sharedBuffer);
        this.canvasInfoFloat = new Float32Array(this.sharedBuffer, CANVAS_INFO_OFFSET, 4);

        this.canvas = new OffscreenCanvas(this.canvasInfoFloat[0], this.canvasInfoFloat[1]);
        this.setupWebGL(this.canvas);

        if (!this.gl) {
            self.postMessage({ type: "error", message: "Failed to initialize WebGL in worker" });
            return;
        }

        let result;
        if (typeof msg.wasmUrl === "string") {
            const response = await fetch(msg.wasmUrl);
            result = await WebAssembly.instantiateStreaming(response, this.imports);
        } else {
            result = await WebAssembly.instantiate(msg.wasmUrl, this.imports);
        }

        this.setInstance(result.instance);
        this.debugLog("wasm loaded", { has_main: !!this.instance.exports.main });

        this.updateCanvasInfo();
        const w = this.cachedPixelWidth || 800;
        const h = this.cachedPixelHeight || 600;
        this.gl.canvas.width = w;
        this.gl.canvas.height = h;
        this.renderTargetSize = [w, h];
        this.gl.viewport(0, 0, w, h);
        this.gl.scissor(0, 0, w, h);

        self.postMessage({ type: "ready" });
        this.debugLog("worker ready: wasm loaded", { has_main: !!this.instance.exports.main });

        if (!this.instance.exports.main) {
            self.postMessage({ type: "error", message: "Web worker standalone mode requires an exported main() function!" });
            return;
        }

        this.instance.exports.main();
    }

    wasm_sleep(ms) {
        Atomics.wait(this.signalArray, SIGNAL_INDEX, 0, ms);
    }

    wasm_refresh() {
        // No-op in worker mode. The blocking loop drives frames.
    }

    wasm_pixel_width() {
        this.updateCanvasInfo();
        return this.cachedPixelWidth;
    }

    wasm_pixel_height() {
        this.updateCanvasInfo();
        return this.cachedPixelHeight;
    }

    wasm_canvas_width() {
        this.updateCanvasInfo();
        return this.cachedCanvasWidth;
    }

    wasm_canvas_height() {
        this.updateCanvasInfo();
        return this.cachedCanvasHeight;
    }

    wasm_canvas_info(out_pw, out_ph, out_cw, out_ch) {
        this.updateCanvasInfo();
        const mem = new Float32Array(this.instance.exports.memory.buffer);
        mem[out_pw >> 2] = this.cachedPixelWidth;
        mem[out_ph >> 2] = this.cachedPixelHeight;
        mem[out_cw >> 2] = this.cachedCanvasWidth;
        mem[out_ch >> 2] = this.cachedCanvasHeight;
    }

    wasm_wait_event(timeout_ms) {
        this.debugWaitCalls++;
        const drainedBeforeWait = this.drainEvents();

        this.updateCanvasInfo();
        const w = this.cachedPixelWidth;
        const h = this.cachedPixelHeight;
        this.syncCanvasSize(w, h);

        Atomics.store(this.signalArray, SIGNAL_INDEX, 0);

        const writeCursor = Atomics.load(this.signalArray, WRITE_CURSOR_INDEX);
        const readCursor = Atomics.load(this.signalArray, READ_CURSOR_INDEX);
        
        if (writeCursor !== readCursor) {
            const drainedQueued = this.drainEvents();
            return (drainedBeforeWait + drainedQueued) > 0 ? 1 : 0;
        }

        if (timeout_ms === 0) {
            return 0;
        }

        timeout_ms < 0
            ? Atomics.wait(this.signalArray, SIGNAL_INDEX, 0)
            : Atomics.wait(this.signalArray, SIGNAL_INDEX, 0, timeout_ms);

        const drainedAfterWait = this.drainEvents();
        return (drainedBeforeWait + drainedAfterWait) > 0 ? 1 : 0;
    }

    wasm_preferred_color_scheme() {
        return Atomics.load(this.signalArray, COLOR_SCHEME_INDEX);
    }

    wasm_renderTarget(id) {
        super.wasm_renderTarget(id);
        if (this.debugEnabled) {
            this.debugLog("renderTarget", {
                id,
                using_fb: this.using_fb,
                renderTargetSize: this.renderTargetSize,
                drawingBuffer: [this.gl.drawingBufferWidth, this.gl.drawingBufferHeight],
                canvasSize: [this.gl.canvas.width, this.gl.canvas.height],
            });
        }
    }

    wasm_renderGeometry(
        textureId,
        index_ptr,
        index_len,
        vertex_ptr,
        vertex_len,
        sizeof_vertex,
        offset_pos,
        offset_col,
        offset_uv,
        clip,
        x,
        y,
        w,
        h,
    ) {
        super.wasm_renderGeometry(...arguments);
    }

    wasm_send_offscreencanvas_bitmap() {
        const bitmap = this.canvas.transferToImageBitmap();
        self.postMessage({ type: "bitmap", bitmap: bitmap }, [bitmap]);
    }

    wasm_cursor(name_ptr, name_len) {
        const cursor_name = this.stringFromPointer(name_ptr, name_len);
        self.postMessage({ type: "cursor", cursor: cursor_name });
    }

    wasm_text_input(x, y, w, h) {
        self.postMessage({ type: "text_input", rect: [x, y, w, h] });
    }

    wasm_open_url(ptr, len, new_win) {
        const url = this.stringFromPointer(ptr, len);
        self.postMessage({ type: "open_url", url, new_window: !!new_win });
    }

    wasm_download_data(name_ptr, name_len, data_ptr, data_len) {
        const name = this.stringFromPointer(name_ptr, name_len);
        const data = new Uint8Array(this.bytesFromPointer(data_ptr, data_len));
        self.postMessage({ type: "download", name, data }, [data.buffer]);
    }

    wasm_clipboardTextSet(ptr, len) {
        if (len === 0) return;
        const text = this.stringFromPointer(ptr, len);
        self.postMessage({ type: "clipboard_set", text });
    }

    wasm_open_file_picker(id, accept_ptr, accept_len, multiple) {
        const accept = this.stringFromPointer(accept_ptr, accept_len);
        self.postMessage({ type: "file_picker", id, accept, multiple: !!multiple });
    }

    wasm_get_number_of_files_available(_id) {
        return 0;
    }

    wasm_get_file_name(_id, _file_index) {
        return 0;
    }

    wasm_get_file_size(_id, _file_index) {
        return -1;
    }

    wasm_read_file_data(_id, _file_index, _data) { }

    wasm_add_noto_font() {
        fetch("NotoSansKR-Regular.ttf")
            .then(r => r.arrayBuffer())
            .then(buf => {
                const bytes = new Uint8Array(buf);
                const ptr = this.allocBuffer(this.instance.exports.gpa_u8, bytes);
                this.instance.exports.new_font(ptr, bytes.length);
            });
    }

    wasm_panic(ptr, len) {
        const msg = this.stringFromPointer(ptr, len);
        console.error("WASM PANIC:", msg);
        self.postMessage({ type: "panic", message: msg });
    }
}

self.onmessage = async function (e) {
    const msg = e.data;
    if (msg.type === "init") {
        const renderer = new WorkerRenderer();
        try {
            await renderer.init(msg);
        } catch (err) {
            console.error("Worker WASM error:", err);
            self.postMessage({ type: "error", message: err?.stack || err?.toString?.() || "unknown worker error" });
        }
    }
};
