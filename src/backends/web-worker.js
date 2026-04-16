/// @file web-worker.js
/// Worker-side script for dvui standalone mode.
/// Runs WASM in a Web Worker with OffscreenCanvas for WebGL rendering.
/// Events arrive via SharedArrayBuffer from the main thread.
///
/// Protocol for SharedArrayBuffer layout:
///   Int32[0]  = signal flag (Atomics.wait/notify)
///   Int32[1]  = event write cursor (main thread writes, worker reads)
///   Int32[2]  = event read cursor (worker writes, main thread reads)
///   Float32[4..4+8] = canvas info: pixelW, pixelH, canvasW, canvasH, scaleX, scaleY, pad, pad
///   Bytes[EVENT_RING_OFFSET..] = event ring buffer
///
/// Each event in the ring is 20 bytes:
///   u8 kind, 3 bytes padding, u32 int1, u32 int2, f32 float1, f32 float2

const SIGNAL_INDEX = 0;
const WRITE_CURSOR_INDEX = 1;
const READ_CURSOR_INDEX = 2;
const CANVAS_INFO_OFFSET = 16; // byte offset for canvas info (4 floats)
const EVENT_RING_OFFSET = 256; // byte offset where event ring starts
const EVENT_SIZE = 20;
const MAX_EVENTS = 256;
const RING_SIZE = EVENT_SIZE * MAX_EVENTS;

const utf8decoder = new TextDecoder();
const utf8encoder = new TextEncoder();

const vertexShaderSource_webgl2 = `# version 300 es
    precision mediump float;
    in vec4 aVertexPosition;
    in vec4 aVertexColor;
    in vec2 aTextureCoord;
    uniform mat4 uMatrix;
    out vec4 vColor;
    out vec2 vTextureCoord;
    void main() {
      gl_Position = uMatrix * aVertexPosition;
      vColor = aVertexColor / 255.0;
      vTextureCoord = aTextureCoord;
    }
`;

const vertexShaderSource_webgl = `
    precision mediump float;
    attribute vec4 aVertexPosition;
    attribute vec4 aVertexColor;
    attribute vec2 aTextureCoord;
    uniform mat4 uMatrix;
    varying vec4 vColor;
    varying vec2 vTextureCoord;
    void main() {
      gl_Position = uMatrix * aVertexPosition;
      vColor = aVertexColor / 255.0;
      vTextureCoord = aTextureCoord;
    }
`;

const fragmentShaderSource_webgl2 = `# version 300 es
    precision mediump float;
    in vec4 vColor;
    in vec2 vTextureCoord;
    uniform sampler2D uSampler;
    uniform bool useTex;
    out vec4 fragColor;
    void main() {
        if (useTex) {
            fragColor = texture(uSampler, vTextureCoord) * vColor;
        } else {
            fragColor = vColor;
        }
    }
`;

const fragmentShaderSource_webgl = `
    precision mediump float;
    varying vec4 vColor;
    varying vec2 vTextureCoord;
    uniform sampler2D uSampler;
    uniform bool useTex;
    void main() {
        if (useTex) {
            gl_FragColor = texture2D(uSampler, vTextureCoord) * vColor;
        } else {
            gl_FragColor = vColor;
        }
    }
`;

/** @type {SharedArrayBuffer} */
let sharedBuffer;
/** @type {Int32Array} */
let signalArray;
/** @type {Float32Array} */
let canvasInfoFloat;
/** @type {Uint8Array} */
let eventRingBytes;

/** @type {WebGL2RenderingContext | WebGLRenderingContext} */
let gl;
let instance;
let textures = new Map();
let newTextureId = 1;
let using_fb = false;
let frame_buffer = null;
let renderTargetSize = [0, 0];
let shaderProgram;
let programInfo;
let indexBuffer;
let vertexBuffer;
let console_string = "";

// Cached canvas dimensions (updated from SharedArrayBuffer each frame)
let cachedPixelWidth = 800;
let cachedPixelHeight = 600;
let cachedCanvasWidth = 800;
let cachedCanvasHeight = 600;

function isWebGL2() {
    return gl instanceof WebGL2RenderingContext;
}

function stringFromPointer(ptr, length) {
    return utf8decoder.decode(bytesFromPointer(ptr, length));
}

function bytesFromPointer(ptr, length) {
    return new Uint8Array(instance.exports.memory.buffer, ptr, length);
}

function allocBuffer(allocFn, bytes) {
    const pointer = allocFn(bytes.length);
    const slice = new Uint8Array(instance.exports.memory.buffer, pointer, bytes.length);
    slice.set(bytes);
    return pointer;
}

function allocStringZ(allocFn, string, sentinel = 0) {
    const buffer = utf8encoder.encode(string);
    const pointer = allocFn(buffer.length + 1);
    const slice = new Uint8Array(instance.exports.memory.buffer, pointer, buffer.length + 1);
    slice.set(buffer);
    slice[buffer.length] = sentinel;
    return pointer;
}

/** Read canvas info from SharedArrayBuffer */
function updateCanvasInfo() {
    cachedPixelWidth = canvasInfoFloat[0];
    cachedPixelHeight = canvasInfoFloat[1];
    cachedCanvasWidth = canvasInfoFloat[2];
    cachedCanvasHeight = canvasInfoFloat[3];
}

/** Drain all pending events from the ring buffer and call add_event for each */
function drainEvents() {
    const writeCursor = Atomics.load(signalArray, WRITE_CURSOR_INDEX);
    let readCursor = Atomics.load(signalArray, READ_CURSOR_INDEX);

    while (readCursor !== writeCursor) {
        const offset = EVENT_RING_OFFSET + (readCursor % MAX_EVENTS) * EVENT_SIZE;
        const view = new DataView(sharedBuffer, offset, EVENT_SIZE);
        const kind = view.getUint8(0);
        const int1 = view.getUint32(4, true);
        const int2 = view.getUint32(8, true);
        const float1 = view.getFloat32(12, true);
        const float2 = view.getFloat32(16, true);

        if (kind === 5 || kind === 6 || kind === 7) {
            // Key/text events: int1 is a pointer to a string that was allocated
            // by the main thread into the wasm memory. We pass it through directly.
            // The main thread wrote the string bytes into wasm memory via the
            // shared memory (which IS the wasm memory since we use shared memory).
            //
            // Actually in Worker mode, the main thread can't write to wasm memory
            // directly. Instead, the key string is packed into the ring buffer itself.
            // int1 = length of key string, int2 = 0
            // The key string bytes follow the 20-byte event header.
            // But our ring slots are fixed at 20 bytes, so for key events we need
            // a different approach.
            //
            // Simplification: for key events, the main thread encodes the key
            // string into a compact u32 hash and passes it as int1. The wasm side
            // will need to handle this. However, the existing add_event protocol
            // expects a pointer+length for key events.
            //
            // Best approach: the main thread writes the key string into a small
            // dedicated area of the SharedArrayBuffer, and passes offset+length.
            // For now, we allocate wasm memory in the worker and copy the string.
            //
            // The main thread packs key strings into a separate string area of the
            // SharedArrayBuffer. int1 = offset into string area, int2 = length.
            const strOffset = int1;
            const strLen = int2;
            if (strLen > 0 && strLen < 256) {
                const strBytes = new Uint8Array(sharedBuffer, STRING_AREA_OFFSET + strOffset, strLen);
                const ptr = allocBuffer(instance.exports.arena_u8, strBytes);
                instance.exports.add_event(kind, ptr, strLen, float1, float2);
            }
        } else {
            instance.exports.add_event(kind, int1, int2, float1, float2);
        }

        readCursor++;
        Atomics.store(signalArray, READ_CURSOR_INDEX, readCursor);
    }
}

const STRING_AREA_OFFSET = EVENT_RING_OFFSET + RING_SIZE;
const STRING_AREA_SIZE = 4096;

function setupWebGL(canvas) {
    gl = canvas.getContext("webgl2", { alpha: true, antialias: false });
    if (gl === null) {
        gl = canvas.getContext("webgl", { alpha: true, antialias: false });
    }
    if (gl === null) {
        console.error("Unable to initialize WebGL in worker.");
        return;
    }

    frame_buffer = gl.createFramebuffer();

    const vertexShader = gl.createShader(gl.VERTEX_SHADER);
    gl.shaderSource(vertexShader, isWebGL2() ? vertexShaderSource_webgl2 : vertexShaderSource_webgl);
    gl.compileShader(vertexShader);
    if (!gl.getShaderParameter(vertexShader, gl.COMPILE_STATUS)) {
        console.error("Vertex shader error:", gl.getShaderInfoLog(vertexShader));
        return;
    }

    const fragmentShader = gl.createShader(gl.FRAGMENT_SHADER);
    gl.shaderSource(fragmentShader, isWebGL2() ? fragmentShaderSource_webgl2 : fragmentShaderSource_webgl);
    gl.compileShader(fragmentShader);
    if (!gl.getShaderParameter(fragmentShader, gl.COMPILE_STATUS)) {
        console.error("Fragment shader error:", gl.getShaderInfoLog(fragmentShader));
        return;
    }

    shaderProgram = gl.createProgram();
    gl.attachShader(shaderProgram, vertexShader);
    gl.attachShader(shaderProgram, fragmentShader);
    gl.linkProgram(shaderProgram);
    if (!gl.getProgramParameter(shaderProgram, gl.LINK_STATUS)) {
        console.error("Shader link error:", gl.getProgramInfoLog(shaderProgram));
        return;
    }

    programInfo = {
        attribLocations: {
            vertexPosition: gl.getAttribLocation(shaderProgram, "aVertexPosition"),
            vertexColor: gl.getAttribLocation(shaderProgram, "aVertexColor"),
            textureCoord: gl.getAttribLocation(shaderProgram, "aTextureCoord"),
        },
        uniformLocations: {
            matrix: gl.getUniformLocation(shaderProgram, "uMatrix"),
            uSampler: gl.getUniformLocation(shaderProgram, "uSampler"),
            useTex: gl.getUniformLocation(shaderProgram, "useTex"),
        },
    };

    indexBuffer = gl.createBuffer();
    vertexBuffer = gl.createBuffer();

    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    gl.enable(gl.SCISSOR_TEST);
}

/** Build the wasm import object matching dvui's extern "dvui" declarations */
function buildImports() {
    return {
        dvui: {
            wasm_about_webgl2: () => isWebGL2() ? 1 : 0,
            wasm_panic: (ptr, len) => {
                const msg = stringFromPointer(ptr, len);
                console.error("WASM PANIC:", msg);
                // Notify main thread of panic
                self.postMessage({ type: "panic", message: msg });
            },
            wasm_console_drain: (ptr, len) => {
                console_string += stringFromPointer(ptr, len);
            },
            wasm_console_flush: (level) => {
                switch (level) {
                    case 9: console.error(console_string); break;
                    case 7: console.warn(console_string); break;
                    case 5: console.info(console_string); break;
                    case 3: console.debug(console_string); break;
                    default: console.log(console_string); break;
                }
                console_string = "";
            },
            wasm_now: () => performance.now(),
            wasm_sleep: (ms) => {
                // In Worker we can actually block
                Atomics.wait(signalArray, SIGNAL_INDEX, 0, ms);
            },
            wasm_refresh: () => {
                // No-op in worker mode. The blocking loop drives frames.
            },
            wasm_pixel_width: () => {
                updateCanvasInfo();
                return cachedPixelWidth;
            },
            wasm_pixel_height: () => {
                updateCanvasInfo();
                return cachedPixelHeight;
            },
            wasm_canvas_width: () => {
                updateCanvasInfo();
                return cachedCanvasWidth;
            },
            wasm_canvas_height: () => {
                updateCanvasInfo();
                return cachedCanvasHeight;
            },
            wasm_frame_buffer: () => using_fb ? 1 : 0,
            wasm_wait_event: (timeout_ms) => {
                // Drain any pending events first
                drainEvents();

                // Update canvas size for rendering
                updateCanvasInfo();
                const w = cachedPixelWidth;
                const h = cachedPixelHeight;
                if (w > 0 && h > 0) {
                    gl.canvas.width = w;
                    gl.canvas.height = h;
                    renderTargetSize = [w, h];
                    gl.viewport(0, 0, w, h);
                    gl.scissor(0, 0, w, h);
                }

                gl.clearColor(0.0, 0.0, 0.0, 1.0);
                gl.clear(gl.COLOR_BUFFER_BIT);

                // Reset the signal so we can wait on it
                Atomics.store(signalArray, SIGNAL_INDEX, 0);

                // Check if events arrived while we were rendering
                const writeCursor = Atomics.load(signalArray, WRITE_CURSOR_INDEX);
                const readCursor = Atomics.load(signalArray, READ_CURSOR_INDEX);
                if (writeCursor !== readCursor) {
                    drainEvents();
                    return 1; // interrupted by event
                }

                if (timeout_ms === 0) return 0;

                // Block until notified or timeout
                const result = timeout_ms < 0
                    ? Atomics.wait(signalArray, SIGNAL_INDEX, 0)
                    : Atomics.wait(signalArray, SIGNAL_INDEX, 0, timeout_ms);

                // Drain any events that arrived
                drainEvents();

                return result === "ok" ? 1 : 0; // "ok" = was notified, "timed-out" = timeout
            },
            wasm_canvas_info: (out_pw, out_ph, out_cw, out_ch) => {
                updateCanvasInfo();
                const mem = new Float32Array(instance.exports.memory.buffer);
                mem[out_pw >> 2] = cachedPixelWidth;
                mem[out_ph >> 2] = cachedPixelHeight;
                mem[out_cw >> 2] = cachedCanvasWidth;
                mem[out_ch >> 2] = cachedCanvasHeight;
            },
            wasm_textureCreate: (pixels, width, height, interp) => {
                const pixelData = bytesFromPointer(pixels, width * height * 4);
                const texture = gl.createTexture();
                const id = newTextureId++;
                textures.set(id, [texture, width, height]);
                gl.bindTexture(gl.TEXTURE_2D, texture);
                gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixelData);
                if (isWebGL2()) gl.generateMipmap(gl.TEXTURE_2D);
                const filter = interp === 0 ? gl.NEAREST : gl.LINEAR;
                gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
                gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
                gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
                gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
                gl.bindTexture(gl.TEXTURE_2D, null);
                return id;
            },
            wasm_textureCreateTarget: (width, height, interp) => {
                const texture = gl.createTexture();
                const id = newTextureId++;
                textures.set(id, [texture, width, height]);
                gl.bindTexture(gl.TEXTURE_2D, texture);
                gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
                const filter = interp === 0 ? gl.NEAREST : gl.LINEAR;
                gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
                gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
                gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
                gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
                gl.bindTexture(gl.TEXTURE_2D, null);
                // Clear the target
                gl.bindFramebuffer(gl.FRAMEBUFFER, frame_buffer);
                gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
                gl.clearColor(0.0, 0.0, 0.0, 0.0);
                gl.clear(gl.COLOR_BUFFER_BIT);
                gl.bindFramebuffer(gl.FRAMEBUFFER, null);
                return id;
            },
            wasm_textureClearTarget: (textureId) => {
                gl.bindFramebuffer(gl.FRAMEBUFFER, frame_buffer);
                gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, textures.get(textureId)[0], 0);
                gl.clearColor(0.0, 0.0, 0.0, 0.0);
                gl.clear(gl.COLOR_BUFFER_BIT);
                gl.bindFramebuffer(gl.FRAMEBUFFER, null);
            },
            wasm_textureRead: (textureId, pixels_out, width, height) => {
                gl.bindFramebuffer(gl.FRAMEBUFFER, frame_buffer);
                gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, textures.get(textureId)[0], 0);
                const dest = bytesFromPointer(pixels_out, width * height * 4);
                gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, dest, 0);
                gl.bindFramebuffer(gl.FRAMEBUFFER, null);
            },
            wasm_renderTarget: (id) => {
                if (id === 0) {
                    using_fb = false;
                    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
                    renderTargetSize = [gl.drawingBufferWidth, gl.drawingBufferHeight];
                } else {
                    using_fb = true;
                    gl.bindFramebuffer(gl.FRAMEBUFFER, frame_buffer);
                    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, textures.get(id)[0], 0);
                    renderTargetSize = [textures.get(id)[1], textures.get(id)[2]];
                }
                gl.viewport(0, 0, renderTargetSize[0], renderTargetSize[1]);
                gl.scissor(0, 0, renderTargetSize[0], renderTargetSize[1]);
            },
            wasm_textureDestroy: (id) => {
                const texture = textures.get(id)[0];
                textures.delete(id);
                gl.deleteTexture(texture);
            },
            wasm_renderGeometry: (textureId, index_ptr, index_len, vertex_ptr, vertex_len,
                sizeof_vertex, offset_pos, offset_col, offset_uv, clip, x, y, w, h) => {
                if (clip === 1) gl.scissor(x, y, w, h);

                gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer);
                const indices = new Uint16Array(instance.exports.memory.buffer, index_ptr, index_len / 2);
                gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.DYNAMIC_DRAW);

                gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
                const vertexes = bytesFromPointer(vertex_ptr, vertex_len);
                gl.bufferData(gl.ARRAY_BUFFER, vertexes, gl.DYNAMIC_DRAW);

                let matrix = new Float32Array(16);
                matrix[0] = 2.0 / renderTargetSize[0];
                matrix[5] = using_fb ? (2.0 / renderTargetSize[1]) : (-2.0 / renderTargetSize[1]);
                matrix[10] = 1.0;
                matrix[12] = -1.0;
                matrix[13] = using_fb ? -1.0 : 1.0;
                matrix[15] = 1.0;

                gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
                gl.vertexAttribPointer(programInfo.attribLocations.vertexPosition, 2, gl.FLOAT, false, sizeof_vertex, offset_pos);
                gl.enableVertexAttribArray(programInfo.attribLocations.vertexPosition);
                gl.vertexAttribPointer(programInfo.attribLocations.vertexColor, 4, gl.UNSIGNED_BYTE, false, sizeof_vertex, offset_col);
                gl.enableVertexAttribArray(programInfo.attribLocations.vertexColor);
                gl.vertexAttribPointer(programInfo.attribLocations.textureCoord, 2, gl.FLOAT, false, sizeof_vertex, offset_uv);
                gl.enableVertexAttribArray(programInfo.attribLocations.textureCoord);

                gl.useProgram(shaderProgram);
                gl.uniformMatrix4fv(programInfo.uniformLocations.matrix, false, matrix);

                if (textureId !== 0) {
                    gl.activeTexture(gl.TEXTURE0);
                    gl.bindTexture(gl.TEXTURE_2D, textures.get(textureId)[0]);
                    gl.uniform1i(programInfo.uniformLocations.useTex, 1);
                } else {
                    gl.bindTexture(gl.TEXTURE_2D, null);
                    gl.uniform1i(programInfo.uniformLocations.useTex, 0);
                }
                gl.uniform1i(programInfo.uniformLocations.uSampler, 0);

                gl.drawElements(gl.TRIANGLES, indices.length, gl.UNSIGNED_SHORT, 0);

                if (clip === 1) {
                    gl.scissor(0, 0, renderTargetSize[0], renderTargetSize[1]);
                }
            },
            wasm_cursor: (name_ptr, name_len) => {
                const cursor_name = stringFromPointer(name_ptr, name_len);
                self.postMessage({ type: "cursor", cursor: cursor_name });
            },
            wasm_text_input: (x, y, w, h) => {
                self.postMessage({ type: "text_input", rect: [x, y, w, h] });
            },
            wasm_open_url: (ptr, len, new_win) => {
                const url = stringFromPointer(ptr, len);
                self.postMessage({ type: "open_url", url, new_window: !!new_win });
            },
            wasm_preferred_color_scheme: () => {
                // Can't access window.matchMedia from worker.
                // Main thread writes it to shared buffer. Use a fixed location.
                return Atomics.load(signalArray, 3); // index 3 = color scheme
            },
            wasm_download_data: (name_ptr, name_len, data_ptr, data_len) => {
                const name = stringFromPointer(name_ptr, name_len);
                const data = new Uint8Array(bytesFromPointer(data_ptr, data_len));
                self.postMessage({ type: "download", name, data }, [data.buffer]);
            },
            wasm_clipboardTextSet: (ptr, len) => {
                if (len === 0) return;
                const text = stringFromPointer(ptr, len);
                self.postMessage({ type: "clipboard_set", text });
            },
            wasm_open_file_picker: (id, accept_ptr, accept_len, multiple) => {
                const accept = stringFromPointer(accept_ptr, accept_len);
                self.postMessage({ type: "file_picker", id, accept, multiple: !!multiple });
            },
            wasm_get_number_of_files_available: (_id) => 0,
            wasm_get_file_name: (_id, _file_index) => 0,
            wasm_get_file_size: (_id, _file_index) => -1,
            wasm_read_file_data: (_id, _file_index, _data) => {},
            wasm_add_noto_font: () => {
                // Fetch and add font
                fetch("NotoSansKR-Regular.ttf")
                    .then(r => r.arrayBuffer())
                    .then(buf => {
                        const bytes = new Uint8Array(buf);
                        const ptr = allocBuffer(instance.exports.gpa_u8, bytes);
                        instance.exports.new_font(ptr, bytes.length);
                    });
            },
        },
    };
}

// Handle messages from main thread
self.onmessage = async function(e) {
    const msg = e.data;

    if (msg.type === "init") {
        sharedBuffer = msg.sharedBuffer;
        signalArray = new Int32Array(sharedBuffer);
        canvasInfoFloat = new Float32Array(sharedBuffer, CANVAS_INFO_OFFSET, 4);
        eventRingBytes = new Uint8Array(sharedBuffer, EVENT_RING_OFFSET, RING_SIZE + STRING_AREA_SIZE);

        const canvas = msg.canvas; // OffscreenCanvas
        setupWebGL(canvas);

        if (!gl) {
            self.postMessage({ type: "error", message: "Failed to initialize WebGL in worker" });
            return;
        }

        // Load WASM
        const imports = buildImports();
        const wasmUrl = msg.wasmUrl;

        try {
            let result;
            if (typeof wasmUrl === "string") {
                const response = await fetch(wasmUrl);
                result = await WebAssembly.instantiateStreaming(response, imports);
            } else {
                result = await WebAssembly.instantiate(wasmUrl, imports);
            }

            instance = result.instance;

            // Set initial canvas size
            updateCanvasInfo();
            const w = cachedPixelWidth || 800;
            const h = cachedPixelHeight || 600;
            gl.canvas.width = w;
            gl.canvas.height = h;
            renderTargetSize = [w, h];
            gl.viewport(0, 0, w, h);
            gl.scissor(0, 0, w, h);

            self.postMessage({ type: "ready" });

            // Call dvui_main which runs the blocking main loop
            if (instance.exports.dvui_main) {
                instance.exports.dvui_main();
            } else if (instance.exports.dvui_init) {
                // Fallback to classic init/update loop
                const platformStr = utf8encoder.encode(msg.platform || "");
                let initRet = 0;
                if (platformStr.length > 0) {
                    const ptr = allocBuffer(instance.exports.gpa_u8, platformStr);
                    initRet = instance.exports.dvui_init(ptr, platformStr.length);
                    instance.exports.gpa_free(ptr, platformStr.length);
                } else {
                    initRet = instance.exports.dvui_init(0, 0);
                }
                if (initRet !== 0) {
                    self.postMessage({ type: "error", message: "dvui_init returned " + initRet });
                    return;
                }

                // Run update loop
                while (true) {
                    updateCanvasInfo();
                    const pw = cachedPixelWidth;
                    const ph = cachedPixelHeight;
                    if (pw > 0 && ph > 0) {
                        gl.canvas.width = pw;
                        gl.canvas.height = ph;
                        renderTargetSize = [pw, ph];
                        gl.viewport(0, 0, pw, ph);
                        gl.scissor(0, 0, pw, ph);
                    }
                    gl.clearColor(0.0, 0.0, 0.0, 1.0);
                    gl.clear(gl.COLOR_BUFFER_BIT);

                    drainEvents();
                    const millis = instance.exports.dvui_update();
                    if (millis < 0) break;

                    if (millis > 0) {
                        Atomics.store(signalArray, SIGNAL_INDEX, 0);
                        Atomics.wait(signalArray, SIGNAL_INDEX, 0, millis);
                    }
                }
            } else {
                self.postMessage({ type: "error", message: "No dvui_main or dvui_init export found" });
            }
        } catch (err) {
            console.error("Worker WASM error:", err);
            self.postMessage({ type: "error", message: err.toString() });
        }
    }
};
