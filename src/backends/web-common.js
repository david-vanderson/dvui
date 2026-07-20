/**
 * Fetch a url and return its body as bytes.
 * @param {string} url
 * @returns {Promise<Uint8Array>}
 */
export async function dvui_fetch(url) {
    let x = await fetch(url);
    let blob = await x.blob();
    //console.log("dvui_fetch: " + blob.size);
    return new Uint8Array(await blob.arrayBuffer());
}

export const vertexShaderSource_webgl = `
    precision mediump float;

    attribute vec4 aVertexPosition;
    attribute vec4 aVertexColor;
    attribute vec2 aTextureCoord;

    uniform mat4 uMatrix;

    varying vec4 vColor;
    varying vec2 vTextureCoord;

    void main() {
      gl_Position = uMatrix * aVertexPosition;
      vColor = aVertexColor / 255.0;  // normalize u8 colors to 0-1
      vTextureCoord = aTextureCoord;
    }
`;

export const vertexShaderSource_webgl2 = `# version 300 es

    precision mediump float;

    in vec4 aVertexPosition;
    in vec4 aVertexColor;
    in vec2 aTextureCoord;

    uniform mat4 uMatrix;

    out vec4 vColor;
    out vec2 vTextureCoord;

    void main() {
      gl_Position = uMatrix * aVertexPosition;
      vColor = aVertexColor / 255.0;  // normalize u8 colors to 0-1
      vTextureCoord = aTextureCoord;
    }
`;

export const fragmentShaderSource_webgl = `
    precision mediump float;

    varying vec4 vColor;
    varying vec2 vTextureCoord;

    uniform sampler2D uSampler;
    uniform bool useTex;

    void main() {
        if (useTex) {
            gl_FragColor = texture2D(uSampler, vTextureCoord) * vColor;
        }
        else {
            gl_FragColor = vColor;
        }
    }
`;

export const fragmentShaderSource_webgl2 = `# version 300 es

    precision mediump float;

    in vec4 vColor;
    in vec2 vTextureCoord;

    uniform sampler2D uSampler;
    uniform bool useTex;

    out vec4 fragColor;

    void main() {
        if (useTex) {
            fragColor = texture(uSampler, vTextureCoord) * vColor;
        }
        else {
            fragColor = vColor;
        }
    }
`;

export const utf8decoder = new TextDecoder();
export const utf8encoder = new TextEncoder();

/// Shared memory layout protocol between main thread and worker for standalone mode.

/// Protocol for SharedArrayBuffer layout (Total Size: 9,472 bytes):
///   Int32[0]          = signal flag (Atomics.wait/notify)
///   Int32[1]          = event write cursor (main thread writes, worker reads)
///   Int32[2]          = event read cursor (worker writes, main thread reads)
///   Int32[3]          = preferred color scheme (0 = system/unknown, 1 = dark, 2 = light)
///   Float32[4..7]     = canvas info (byte offset 16):
///                       Float32[4] = pixel width
///                       Float32[5] = pixel height
///                       Float32[6] = canvas (CSS) width
///                       Float32[7] = canvas (CSS) height
///   Bytes[256..5375]  = event ring buffer (EVENT_RING_OFFSET, size: 5,120 bytes)
///   Bytes[5376..9471] = string storage area (STRING_AREA_OFFSET, size: 4,096 bytes)
///
/// Each event in the ring is 20 bytes:
///   u8 kind, 3 bytes padding, u32 int1, u32 int2, f32 float1, f32 float2

export const SIGNAL_INDEX = 0;
export const WRITE_CURSOR_INDEX = 1;
export const READ_CURSOR_INDEX = 2;
export const COLOR_SCHEME_INDEX = 3;

export const CANVAS_INFO_OFFSET = 16;
export const EVENT_RING_OFFSET = 256;
export const EVENT_SIZE = 20;
export const MAX_EVENTS = 256;

export const RING_SIZE = EVENT_SIZE * MAX_EVENTS;
export const STRING_AREA_OFFSET = EVENT_RING_OFFSET + RING_SIZE;
export const STRING_AREA_SIZE = 4096;
export const TOTAL_SHARED_SIZE = STRING_AREA_OFFSET + STRING_AREA_SIZE;

/**
 * Encode modifier keys into a 4-bit value.
 * @param {KeyboardEvent | MouseEvent} ev
 * @returns {number}
 */
export function encodeModifiers(ev) {
    return (ev.metaKey << 3) + (ev.altKey << 2) + (ev.ctrlKey << 1) + (ev.shiftKey << 0);
}

/**
 * Return the existing touch index for pointerId, allocating a new one if needed.
 * @param {[number, number][]} touches
 * @param {number} pointerId
 * @returns {number}
 */
export function touchIndex(touches, pointerId) {
    let idx = touches.findIndex((e) => e[0] === pointerId);
    if (idx < 0) {
        idx = touches.length;
        touches.push([pointerId, idx]);
    }
    return idx;
}

/**
 * Tracks wheel/touchpad scroll deltas and produces normalized tick values.
 */
export class WheelHandler {
    /** The lowest deltaX/Y seen, used to determine the delta for touchpads
     *
     * The first number is x and second is y
     * @type {[number, number]} */
    scrollLowest = [99999, 99999];
    /** The lowest deltaX/Y seen in this batch (resets if none in 1s).  Used to
     * determine if we think a touchpad is being used and also as the delta for
     * mouse wheels.
     *
     * The first number is x and second is y
     * @type {[number, number]} */
    scrollLowestBatch = [99999, 99999];
    scrollLastMs = Date.now();
    touchpadAdj = 0.025;

    /**
     * Process a WheelEvent and return scroll actions.
     * @param {WheelEvent} ev
     * @returns {{axis: number, ticks: number, trackpad: number}[]}
     */
    processWheelEvent(ev) {
        const actions = [];

        if ((Date.now() - this.scrollLastMs) > 1000) {
            this.scrollLowestBatch[0] = 99999;
            this.scrollLowestBatch[1] = 99999;
        }
        this.scrollLastMs = Date.now();

        if (ev.deltaX !== 0) {
            const result = this._processAxis(0, ev.deltaX, ev.deltaMode);
            if (result) actions.push({ axis: 0, ...result });
        }
        if (ev.deltaY !== 0) {
            const result = this._processAxis(1, ev.deltaY, ev.deltaMode);
            if (result) actions.push({ axis: 1, ...result });
        }

        return actions;
    }

    _processAxis(index, delta, deltaMode) {
        const absDelta = Math.abs(delta);
        this.scrollLowest[index] = Math.min(absDelta, this.scrollLowest[index]);
        this.scrollLowestBatch[index] = Math.min(absDelta, this.scrollLowestBatch[index]);

        let ticks = -delta;
        let trackpad = 0;

        if (deltaMode !== 0) {
            // only mouse wheels produce non-pixel deltas, so this is definitive without
            // needing the magnitude heuristic.
            ticks /= this.scrollLowestBatch[index];
        } else if (
            this.scrollLowestBatch[index] >= 100 || // most wheels
            this.scrollLowestBatch[index] === 16 || // mac firefox
            (index === 0 && (
                this.scrollLowestBatch[index] === 9 || // mac firefox holding shift
                this.scrollLowestBatch[index] === 40 // mac safari/chrome holding shift
            )) ||
            this.scrollLowestBatch[index] === 4.000244140625 // mac safari/chrome
        ) {
            // assume this is a mouse wheel
            ticks /= this.scrollLowestBatch[index];
            if (this.scrollLowestBatch[index] === 4.000244140625) {
                ticks *= this.touchpadAdj; // mac safari/chrome scale wheel like touchpad
            }
        } else {
            // assume touchpad
            trackpad = 1;
            ticks = (ticks / this.scrollLowest[index]) * this.touchpadAdj;
        }

        return { ticks, trackpad };
    }
}

//let par = document.createElement("p");
//document.body.prepend(par);

/**
 * Manages a hidden input element for IME / on-screen keyboard support.
 */
export class HiddenInputManager {
    /** @type {HTMLInputElement} */
    hiddenInput;
    /**
     * x y w h of on screen keyboard editing position, or empty if none
     *
     * @type {[number, number, number, number] | []} */
    textInputRect = [];
    /** @type {HTMLElement} */
    target;

    /**
     * @param {HTMLElement} target - Element to position relative to (typically canvas)
     */
    constructor(target) {
        this.target = target;
        this.hiddenInput = document.createElement("input");
        this.hiddenInput.setAttribute("autocapitalize", "none");
        this.hiddenInput.style.position = "absolute";
        this.hiddenInput.style.left = "0";
        this.hiddenInput.style.top = "0";
        // remove extra size so input doesn't cause overflow
        this.hiddenInput.style.padding = "0";
        this.hiddenInput.style.border = "0";
        this.hiddenInput.style.margin = "0";
        this.hiddenInput.style.opacity = "0";
        this.hiddenInput.style.zIndex = "-1";
        document.body.prepend(this.hiddenInput);
    }

    /**
     * Set the on screen keyboard editing position, or empty if none.
     * @param {[number, number, number, number] | []} rect - x y w h
     */
    setRect(rect) {
        if (rect.length === 4 && rect[2] > 0 && rect[3] > 0) {
            this.textInputRect = rect;
        } else {
            this.textInputRect = [];
        }
    }

    // This does 2 things:
    // * on desktop it's needed for us to get text events (not just char down/up)
    // * on touch it's needed to show the on screen keyboard
    check() {
        if (this.textInputRect.length === 0) {
            this.target.focus();
        } else {
            const rect = this.target.getBoundingClientRect();
            const left = window.scrollX + rect.left + this.textInputRect[0];
            const top = window.scrollY + rect.top + this.textInputRect[1];
            // limit the width and height to prevent overflow
            const width = Math.max(0, Math.min(this.textInputRect[2], this.target.clientWidth - this.textInputRect[0]));
            const height = Math.max(0, Math.min(this.textInputRect[3], this.target.clientHeight - this.textInputRect[1]));
            this.hiddenInput.style.left = left + "px";
            this.hiddenInput.style.top = top + "px";
            this.hiddenInput.style.width = width + "px";
            this.hiddenInput.style.height = height + "px";
            this.hiddenInput.focus();
            //par.textContent = hiddenInput.style.left + " " + hiddenInput.style.top + " " + hiddenInput.style.width + " " + hiddenInput.style.height;
        }
    }
}

/**
 * Normalize touch coordinates relative to an element's bounding rect.
 * @param {Touch} touch
 * @param {DOMRect} rect
 * @returns {[number, number]}
 */
export function getTouchCoords(touch, rect) {
    return [
        (touch.clientX - rect.left) / (rect.right - rect.left),
        (touch.clientY - rect.top) / (rect.bottom - rect.top),
    ];
}

export class WebRenderer {
    /** @type {WebGL2RenderingContext | WebGLRenderingContext | null} */
    gl = null;
    /** @type {WebGLBuffer | null} */
    indexBuffer = null;
    /** @type {WebGLBuffer | null} */
    vertexBuffer = null;
    /** @type {WebGLProgram | null} */
    shaderProgram = null;
    /** @type {{ attribLocations: { vertexPosition: number;
            vertexColor: number;
            textureCoord: number;
        };
        uniformLocations: {
            matrix: WebGLUniformLocation | null;
            uSampler: WebGLUniformLocation | null;
            useTex: WebGLUniformLocation | null;
        };
    } | null} */
    programInfo = null;
    /** @type {Map<number, [WebGLTexture, number, number]>} */
    textures = new Map();
    newTextureId = 1;

    /** @returns {[WebGLTexture, number, number] | null} */
    textureEntry(id) {
        if (id === 0) return null;
        return this.textures.get(id) ?? null;
    }
    
    using_fb = false;
    /** @type {WebGLFramebuffer | null} */
    frame_buffer = null;
    /** @type {[number, number]} */
    renderTargetSize = [0, 0];

    /** @type {WebAssembly.Instance | null} */
    instance = null;

    console_string = "";

    get webgl2() {
        return this.gl instanceof WebGL2RenderingContext;
    }

    /**
     * @param {DVUI.AllocatorFunction} allocFn
     * @param {number} len
     * @returns {[pointer: number, slice: Uint8Array]}
     */
    genericAlloc(allocFn, len) {
        const pointer = allocFn(len);
        const slice = new Uint8Array(
            this.instance.exports.memory.buffer, 
            pointer, 
            len);
        return [pointer, slice];
    }

    /**
     * @param {DVUI.AllocatorFunction} allocFn
     * @param {ArrayLike<number>} bytes
     * @returns {number} pointer
     */
    allocBuffer(allocFn, bytes) {
        const [pointer, slice] = this.genericAlloc(allocFn, bytes.length);
        slice.set(bytes);
        return pointer;
    }

    /**
     * @param {DVUI.AllocatorFunction} allocFn
     * @param {ArrayLike<number>} bytes
     * @param {number} sentinel
     * @returns {number} pointer
     */
    allocBufferZ(allocFn, bytes, sentinel = 0) {
        const [pointer, slice] = this.genericAlloc(allocFn, bytes.length + 1);
        slice.set(bytes);
        slice[bytes.length] = sentinel;
        return pointer;
    }

    /**
     * @param {DVUI.AllocatorFunction} allocFn
     * @param {string} string
     * @returns {number} pointer
     */
    allocString(allocFn, string) {
        const buffer = utf8encoder.encode(string);
        return this.allocBuffer(allocFn, buffer);
    }

    /**
     * @param {DVUI.AllocatorFunction} allocFn
     * @param {string} string
     * @param {number} sentinel
     * @returns {number} pointer
     */
    allocStringZ(allocFn, string, sentinel = 0) {
        const buffer = utf8encoder.encode(string);
        return this.allocBufferZ(allocFn, buffer, sentinel);
    }

    /**
     * @param {number} ptr
     * @param {number} length
     * @returns {string}
     */
    stringFromPointer(ptr, length) {
        return utf8decoder.decode(this.bytesFromPointer(ptr, length));
    }

    /**
     * @param {number} ptr
     * @param {number} length
     * @returns {Uint8Array}
     */
    bytesFromPointer(ptr, length) {
        return new Uint8Array(this.instance.exports.memory.buffer, ptr, length);
    }

    buildImports() {
        const names = [
            "wasm_about_webgl2",
            "wasm_console_drain",
            "wasm_console_flush",
            "wasm_now",
            "wasm_frame_buffer",
            "wasm_pixel_width",
            "wasm_pixel_height",
            "wasm_canvas_width",
            "wasm_canvas_height",
            "wasm_textureCreate",
            "wasm_textureCreateTarget",
            "wasm_textureClearTarget",
            "wasm_textureRead",
            "wasm_renderTarget",
            "wasm_textureDestroy",
            "wasm_renderGeometry",
            "wasm_download_data",
            "wasm_panic",
            "wasm_sleep",
            "wasm_refresh",
            "wasm_cursor",
            "wasm_text_input",
            "wasm_open_url",
            "wasm_preferred_color_scheme",
            "wasm_prefers_reduced_motion",
            "wasm_open_file_picker",
            "wasm_get_file_size",
            "wasm_get_file_name",
            "wasm_read_file_data",
            "wasm_get_number_of_files_available",
            "wasm_clipboardTextSet",
            "wasm_add_noto_font",
            "wasm_canvas_info",
            "wasm_wait_event",
            "wasm_send_offscreencanvas_bitmap",
        ];
        const imports = {};
        for (const name of names) {
            imports[name] = (...args) => this[name](...args);
        }
        return imports;
    }

    setInstance(instance) {
        this.instance = instance;
    }

    /**
     * @param {HTMLCanvasElement | OffscreenCanvas} canvas
     * @returns {WebGLProgram | null}
     */
    setupWebGL(canvas) {
        this.gl = canvas.getContext("webgl2", { alpha: true, antialias: false });
        if (this.gl === null) {
            this.gl = canvas.getContext("webgl", { alpha: true, antialias: false });
        }
        if (this.gl === null) {
            console.error("Unable to initialize WebGL.");
            return null;
        }

        this.frame_buffer = this.gl.createFramebuffer();

        const gl = this.gl;
        const vertexShader = gl.createShader(gl.VERTEX_SHADER);
        gl.shaderSource(vertexShader, this.webgl2 ? vertexShaderSource_webgl2 : vertexShaderSource_webgl);
        gl.compileShader(vertexShader);
        if (!gl.getShaderParameter(vertexShader, gl.COMPILE_STATUS)) {
            console.error("Vertex shader error:", gl.getShaderInfoLog(vertexShader));
            return null;
        }

        const fragmentShader = gl.createShader(gl.FRAGMENT_SHADER);
        gl.shaderSource(fragmentShader, this.webgl2 ? fragmentShaderSource_webgl2 : fragmentShaderSource_webgl);
        gl.compileShader(fragmentShader);
        if (!gl.getShaderParameter(fragmentShader, gl.COMPILE_STATUS)) {
            console.error("Fragment shader error:", gl.getShaderInfoLog(fragmentShader));
            return null;
        }

        this.shaderProgram = gl.createProgram();
        gl.attachShader(this.shaderProgram, vertexShader);
        gl.attachShader(this.shaderProgram, fragmentShader);
        gl.linkProgram(this.shaderProgram);
        if (!gl.getProgramParameter(this.shaderProgram, gl.LINK_STATUS)) {
            console.error("Shader link error:", gl.getProgramInfoLog(this.shaderProgram));
            return null;
        }

        this.programInfo = {
            attribLocations: {
                vertexPosition: gl.getAttribLocation(this.shaderProgram, "aVertexPosition"),
                vertexColor: gl.getAttribLocation(this.shaderProgram, "aVertexColor"),
                textureCoord: gl.getAttribLocation(this.shaderProgram, "aTextureCoord"),
            },
            uniformLocations: {
                matrix: gl.getUniformLocation(this.shaderProgram, "uMatrix"),
                uSampler: gl.getUniformLocation(this.shaderProgram, "uSampler"),
                useTex: gl.getUniformLocation(this.shaderProgram, "useTex"),
            },
        };

        this.indexBuffer = gl.createBuffer();
        this.vertexBuffer = gl.createBuffer();

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
        gl.enable(gl.SCISSOR_TEST);
        return this.shaderProgram;
    }

    wasm_about_webgl2() {
        if (this.webgl2) {
            return 1;
        } else {
            return 0;
        }
    }

    wasm_panic(ptr, len) {
        const msg = this.stringFromPointer(ptr, len);
        console.error("PANIC:", msg);
    }

    wasm_console_drain(ptr, len) {
        this.console_string += this.stringFromPointer(ptr, len);
    }

    wasm_console_flush(level) {
        switch (level) {
            case 9:
                console.error(this.console_string);
                break;
            case 7:
                console.warn(this.console_string);
                break;
            case 5:
                console.info(this.console_string);
                break;
            case 3:
                console.debug(this.console_string);
                break;
            default:
                console.log(this.console_string);
                break;
        }
        this.console_string = "";
    }

    wasm_now() {
        return performance.now();
    }

    wasm_sleep(_ms) { }

    wasm_refresh() { }

    wasm_pixel_width() {
        return this.gl.drawingBufferWidth;
    }

    wasm_pixel_height() {
        return this.gl.drawingBufferHeight;
    }

    wasm_frame_buffer() {
        if (this.using_fb) {
            return 1;
        } else {
            return 0;
        }
    }

    wasm_canvas_width() {
        return this.gl.canvas.clientWidth;
    }

    wasm_canvas_height() {
        return this.gl.canvas.clientHeight;
    }

    wasm_textureCreate(pixels, width, height, interp, wrap_u, wrap_v) {
        const pixelData = this.bytesFromPointer(pixels, width * height * 4);

        const texture = this.gl.createTexture();
        const id = this.newTextureId;
        //console.log("creating texture " + id);
        this.newTextureId += 1;
        this.textures.set(id, [texture, width, height]);

        this.gl.bindTexture(this.gl.TEXTURE_2D, texture);

        this.gl.texImage2D(
            this.gl.TEXTURE_2D,
            0,
            this.gl.RGBA,
            width,
            height,
            0,
            this.gl.RGBA,
            this.gl.UNSIGNED_BYTE,
            pixelData,
        );

        if (this.webgl2) {
            this.gl.generateMipmap(this.gl.TEXTURE_2D);
        }

        if (interp == 0) {
            this.gl.texParameteri(
                this.gl.TEXTURE_2D,
                this.gl.TEXTURE_MIN_FILTER,
                this.gl.NEAREST,
            );
            this.gl.texParameteri(
                this.gl.TEXTURE_2D,
                this.gl.TEXTURE_MAG_FILTER,
                this.gl.NEAREST,
            );
        } else {
            this.gl.texParameteri(
                this.gl.TEXTURE_2D,
                this.gl.TEXTURE_MIN_FILTER,
                this.gl.LINEAR,
            );
            this.gl.texParameteri(
                this.gl.TEXTURE_2D,
                this.gl.TEXTURE_MAG_FILTER,
                this.gl.LINEAR,
            );
        }
        if (wrap_u === 1) {
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.REPEAT);
        } else {
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
        }
        if (wrap_v === 1) {
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.REPEAT);
        } else {
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);
        }

        this.gl.bindTexture(this.gl.TEXTURE_2D, null);

        return id;
    }

    wasm_textureCreateTarget(width, height, interp, wrap_u, wrap_v) {
        const texture = this.gl.createTexture();
        const id = this.newTextureId;
        //console.log("creating texture " + id);
        this.newTextureId += 1;
        this.textures.set(id, [texture, width, height]);

        this.gl.bindTexture(this.gl.TEXTURE_2D, texture);

        this.gl.texImage2D(
            this.gl.TEXTURE_2D,
            0,
            this.gl.RGBA,
            width,
            height,
            0,
            this.gl.RGBA,
            this.gl.UNSIGNED_BYTE,
            null,
        );

        if (interp == 0) {
            this.gl.texParameteri(
                this.gl.TEXTURE_2D,
                this.gl.TEXTURE_MIN_FILTER,
                this.gl.NEAREST,
            );
            this.gl.texParameteri(
                this.gl.TEXTURE_2D,
                this.gl.TEXTURE_MAG_FILTER,
                this.gl.NEAREST,
            );
        } else {
            this.gl.texParameteri(
                this.gl.TEXTURE_2D,
                this.gl.TEXTURE_MIN_FILTER,
                this.gl.LINEAR,
            );
            this.gl.texParameteri(
                this.gl.TEXTURE_2D,
                this.gl.TEXTURE_MAG_FILTER,
                this.gl.LINEAR,
            );
        }
        if (wrap_u === 1) {
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.REPEAT);
        } else {
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
        }
        if (wrap_v === 1) {
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.REPEAT);
        } else {
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);
        }

        this.gl.bindTexture(this.gl.TEXTURE_2D, null);

        this.wasm_textureClearTarget(id);

        return id;
    }

    wasm_textureClearTarget(textureId) {
        this.wasm_renderTarget(textureId);
        this.gl.clearColor(0.0, 0.0, 0.0, 0.0); // fully transparent
        this.gl.clear(this.gl.COLOR_BUFFER_BIT);
        this.wasm_renderTarget(0);
    }

    wasm_textureRead(textureId, pixels_out, width, height) {
        //console.log("textureRead " + textureId);
        const entry = this.textureEntry(textureId);
        if (entry === null) {
            console.warn(
                `wasm_textureRead: missing texture id ${textureId}`,
            );
            return;
        }
        const texture = entry[0];

        this.gl.bindFramebuffer(
            this.gl.FRAMEBUFFER,
            this.frame_buffer,
        );
        this.gl.framebufferTexture2D(
            this.gl.FRAMEBUFFER,
            this.gl.COLOR_ATTACHMENT0,
            this.gl.TEXTURE_2D,
            texture,
            0,
        );

        var dest = this.bytesFromPointer(pixels_out, width * height * 4);
        this.gl.readPixels(
            0,
            0,
            width,
            height,
            this.gl.RGBA,
            this.gl.UNSIGNED_BYTE,
            dest,
            0,
        );

        this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
    }

    wasm_renderTarget(id) {
        //console.log("renderTarget " + id);
        if (id === 0) {
            this.using_fb = false;
            this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
            this.renderTargetSize = [
                this.gl.drawingBufferWidth,
                this.gl.drawingBufferHeight,
            ];
            this.gl.viewport(
                0,
                0,
                this.renderTargetSize[0],
                this.renderTargetSize[1],
            );
            this.gl.scissor(
                0,
                0,
                this.renderTargetSize[0],
                this.renderTargetSize[1],
            );
        } else {
            this.using_fb = true;
            this.gl.bindFramebuffer(
                this.gl.FRAMEBUFFER,
                this.frame_buffer,
            );

            const rt = this.textureEntry(id);
            if (rt === null) {
                console.warn(
                    `wasm_renderTarget: missing texture id ${id}`,
                );
                this.using_fb = false;
                this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
                this.renderTargetSize = [
                    this.gl.drawingBufferWidth,
                    this.gl.drawingBufferHeight,
                ];
            } else {
                this.gl.framebufferTexture2D(
                    this.gl.FRAMEBUFFER,
                    this.gl.COLOR_ATTACHMENT0,
                    this.gl.TEXTURE_2D,
                    rt[0],
                    0,
                );
                this.renderTargetSize = [rt[1], rt[2]];
            }
            this.gl.viewport(
                0,
                0,
                this.renderTargetSize[0],
                this.renderTargetSize[1],
            );
            this.gl.scissor(
                0,
                0,
                this.renderTargetSize[0],
                this.renderTargetSize[1],
            );
        }
    }

    wasm_textureDestroy(id) {
        //console.log("deleting texture " + id);
        const entry = this.textureEntry(id);
        if (entry === null) return;
        this.textures.delete(id);
        this.gl.deleteTexture(entry[0]);
    }

    buildOrthoMatrix() {
        const matrix = new Float32Array(16);
        matrix[0] = 2.0 / this.renderTargetSize[0];
        matrix[1] = 0.0;
        matrix[2] = 0.0;
        matrix[3] = 0.0;
        matrix[4] = 0.0;
        if (this.using_fb) {
            matrix[5] = 2.0 / this.renderTargetSize[1];
        } else {
            matrix[5] = -2.0 / this.renderTargetSize[1];
        }
        matrix[6] = 0.0;
        matrix[7] = 0.0;
        matrix[8] = 0.0;
        matrix[9] = 0.0;
        matrix[10] = 1.0;
        matrix[11] = 0.0;
        matrix[12] = -1.0;
        if (this.using_fb) {
            matrix[13] = -1.0;
        } else {
            matrix[13] = 1.0;
        }
        matrix[14] = 0.0;
        matrix[15] = 1.0;
        return matrix;
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
        //console.log("drawClippedTriangles " + textureId + " sizeof " + sizeof_vertex + " pos " + offset_pos + " col " + offset_col + " uv " + offset_uv);

        //let old_scissor;
        if (clip === 1) {
            // just calling getParameter here is quite slow (5-10 ms per frame according to chrome)
            //old_scissor = gl.getParameter(gl.SCISSOR_BOX);
            this.gl.scissor(x, y, w, h);
        }

        this.gl.bindBuffer(
            this.gl.ELEMENT_ARRAY_BUFFER,
            this.indexBuffer,
        );
        const indices = new Uint16Array(
            this.instance.exports.memory.buffer,
            index_ptr,
            index_len / 2,
        );
        this.gl.bufferData(
            this.gl.ELEMENT_ARRAY_BUFFER,
            indices,
            this.gl.DYNAMIC_DRAW,
        );

        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.vertexBuffer);
        const vertexes = this.bytesFromPointer(vertex_ptr, vertex_len)
        this.gl.bufferData(
            this.gl.ARRAY_BUFFER,
            vertexes,
            this.gl.DYNAMIC_DRAW,
        );

        let matrix = this.buildOrthoMatrix();

        // vertex
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.vertexBuffer);
        this.gl.vertexAttribPointer(
            this.programInfo.attribLocations.vertexPosition,
            2, // num components
            this.gl.FLOAT,
            false, // don't normalize
            sizeof_vertex, // stride
            offset_pos, // offset
        );
        this.gl.enableVertexAttribArray(
            this.programInfo.attribLocations.vertexPosition,
        );

        // color
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.vertexBuffer);
        this.gl.vertexAttribPointer(
            this.programInfo.attribLocations.vertexColor,
            4, // num components
            this.gl.UNSIGNED_BYTE,
            false, // don't normalize
            sizeof_vertex, // stride
            offset_col, // offset
        );
        this.gl.enableVertexAttribArray(
            this.programInfo.attribLocations.vertexColor,
        );

        // texture
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.vertexBuffer);
        this.gl.vertexAttribPointer(
            this.programInfo.attribLocations.textureCoord,
            2, // num components
            this.gl.FLOAT,
            false, // don't normalize
            sizeof_vertex, // stride
            offset_uv, // offset
        );
        this.gl.enableVertexAttribArray(
            this.programInfo.attribLocations.textureCoord,
        );

        // Tell WebGL to use our program when drawing
        this.gl.useProgram(this.shaderProgram);

        // Set the shader uniforms
        this.gl.uniformMatrix4fv(
            this.programInfo.uniformLocations.matrix,
            false,
            matrix,
        );

        if (textureId != 0) {
            const tex = this.textureEntry(textureId);
            if (tex !== null) {
                this.gl.activeTexture(this.gl.TEXTURE0);
                this.gl.bindTexture(this.gl.TEXTURE_2D, tex[0]);
                this.gl.uniform1i(
                    this.programInfo.uniformLocations.useTex,
                    1,
                );
            } else {
                console.warn(
                    `wasm_renderGeometry: missing texture id ${textureId}`,
                );
                this.gl.bindTexture(this.gl.TEXTURE_2D, null);
                this.gl.uniform1i(
                    this.programInfo.uniformLocations.useTex,
                    0,
                );
            }
        } else {
            this.gl.bindTexture(this.gl.TEXTURE_2D, null);
            this.gl.uniform1i(
                this.programInfo.uniformLocations.useTex,
                0,
            );
        }

        this.gl.uniform1i(
            this.programInfo.uniformLocations.uSampler,
            0,
        );

        //console.log("drawElements " + textureId);
        this.gl.drawElements(
            this.gl.TRIANGLES,
            indices.length,
            this.gl.UNSIGNED_SHORT,
            0,
        );

        if (clip === 1) {
            //gl.scissor(old_scissor[0], old_scissor[1], old_scissor[2], old_scissor[3]);
            this.gl.scissor(
                0,
                0,
                this.renderTargetSize[0],
                this.renderTargetSize[1],
            );
        }
    }

    wasm_cursor(_name_ptr, _name_len) { }

    wasm_text_input(_x, _y, _w, _h) { }

    wasm_open_url(_ptr, _len, _new_win) { }

    wasm_preferred_color_scheme() { return 0; }

    wasm_prefers_reduced_motion() { return 0; }

    wasm_download_data(name_ptr, name_len, data_ptr, data_len) {
        const name = this.stringFromPointer(name_ptr, name_len);
        const data = this.bytesFromPointer(data_ptr, data_len);
        const blob = new Blob([data], { type: "application/octet-stream" });
        const fileURL = URL.createObjectURL(blob);
        const dl = document.createElement("a");
        dl.href = fileURL;
        dl.download = name;
        dl.click();
        dl.remove();
        URL.revokeObjectURL(fileURL);
    }

    wasm_open_file_picker(_id, _accept_ptr, _accept_len, _multiple) { }

    wasm_get_file_size(_id, _file_index) { return -1; }

    wasm_get_file_name(_id, _file_index) { return 0; }

    wasm_read_file_data(_id, _file_index, _data) { }

    wasm_get_number_of_files_available(_id) { return 0; }

    wasm_clipboardTextSet(_ptr, _len) { }

    wasm_add_noto_font() { }

    wasm_canvas_info(_out_pw, _out_ph, _out_cw, _out_ch) { }

    wasm_wait_event(_timeout_ms) { return 0; }

    wasm_send_offscreencanvas_bitmap() { }
}
