/// <reference path="./web.d.ts" />

/**@typedef {BigInt} Id */

/**
 * @param {number} ms Number of milliseconds to sleep
 */
async function dvui_sleep(ms) {
    await new Promise((r) => setTimeout(r, ms));
}

/**
 * @param {string} url
 * @returns {Promise<Uint8Array>}
 */
async function dvui_fetch(url) {
    let x = await fetch(url);
    let blob = await x.blob();
    return new Uint8Array(await blob.arrayBuffer());
}

/**
 * @param {string} accept Maps to the accept attribute of the file input element
 * @param {boolean} multiple
 * @returns {Promise<FileList>}
 */
async function dvui_open_file_picker(accept, multiple) {
    return new Promise((res, rej) => {
        const file_input = document.createElement("input");
        file_input.setAttribute("type", "file");
        file_input.setAttribute("accept", accept);
        if (multiple) {
            file_input.toggleAttribute("multiple", true);
        }
        file_input.oncancel = () => {
            console.trace("File picking cancelled");
            rej("canceled");
        };
        file_input.onchange = () => {
            if (file_input.files.length === 0) {
                console.error("File picker picked no files");
                file_input.oncancel();
            }
            if (!multiple && file_input.files.length > 1) {
                console.error("Picked multiple files in single file picker");
                rej("Too many files");
                return;
            }
            res(file_input.files);
        };
        file_input.click();
    });
}

import { WebRenderer, encodeModifiers, touchIndex } from "./web-common.js";

const utf8encoder = new TextEncoder();

/**
 * @param {string | HTMLCanvasElement} canvas - A canvas element or string id of one
 * @param {DVUI.WasmArg} wasmRef - The url to the wasm file, to be used in `fetch`
 * @returns {Promise<Dvui>}
 */
export function dvui(canvas, wasmRef) {
    const dvui = new Dvui();
    const wasmPromise = typeof wasmRef === "string"
        ? WebAssembly.instantiateStreaming(fetch(wasmRef), dvui.imports)
        : Promise.resolve(wasmRef);
    return wasmPromise.then((result) => {
        dvui.setInstance(result.instance);
        dvui.setCanvas(canvas);
        dvui.run();
        return dvui;
    });
}

export class Dvui extends WebRenderer {
    renderRequested = false;
    renderTimeoutId = 0;
    stopped = false;
    /** @type {HTMLInputElement} */
    hidden_input;
    /** @type {[number, number][]} */
    touches = [];
    /** The lowest deltaX/Y seen, used to determine the delta for touchpads
     *
     * The first number is x and second is y
     * @type {[number, number]} */
    scroll_lowest = [99999, 99999];
    /** The lowest deltaX/Y seen in this batch (resets if none in 1s).  Used to
     * determine if we think a touchpad is being used and also as the delta for
     * mouse wheels.
     *
     * The first number is x and second is y
     * @type {[number, number]} */
    scroll_lowest_batch = [99999, 99999];
    scroll_last_ms = Date.now();
    /**
     * x y w h of on screen keyboard editing position, or empty if none
     *
     * @type {[number, number, number, number] | []} */

    textInputRect = [];
    need_oskCheck = false;

    // Used for file uploads. Only valid for one frame
    filesCacheModified = false;
    /** @type {Map<Id, {files: File[], data: ArrayBuffer[]}>} */
    filesCache = new Map();

    /** @type {WebAssembly.ModuleImports} */
    imports;

    constructor() {
        super();
        this.hidden_input = document.createElement("input");
        this.hidden_input.setAttribute("autocapitalize", "none");
        this.hidden_input.style.position = "absolute";
        this.hidden_input.style.left = 0;
        this.hidden_input.style.top = 0;
        this.hidden_input.style.padding = 0;
        this.hidden_input.style.border = 0;
        this.hidden_input.style.margin = 0;
        this.hidden_input.style.opacity = 0;
        this.hidden_input.style.zIndex = -1;
        document.body.prepend(this.hidden_input);

        this.imports = { dvui: this.buildImports() };
    }

    oskCheck() {
        if (this.textInputRect.length == 0) {
            this.gl.canvas.focus();
        } else {
            const rect = this.gl.canvas.getBoundingClientRect();
            const left = window.scrollX + rect.left + this.textInputRect[0];
            const top = window.scrollY + rect.top + this.textInputRect[1];
            const width = Math.max(
                0,
                Math.min(
                    this.textInputRect[2],
                    this.gl.canvas.clientWidth - left,
                ),
            );
            const height = Math.max(
                0,
                Math.min(
                    this.textInputRect[2],
                    this.gl.canvas.clientHeight - top,
                ),
            );
            this.hidden_input.style.left = left + "px";
            this.hidden_input.style.top = top + "px";
            this.hidden_input.style.width = width + "px";
            this.hidden_input.style.height = height + "px";
            this.hidden_input.focus();
        }
    }

    setupWebGL(canvas) {
        const program = super.setupWebGL(canvas);
        if (!program) {
            alert("Unable to initialize WebGL.");
            return null;
        }
        if (!this.webgl2) {
            const ext = this.gl.getExtension("OES_element_index_uint");
            if (ext === null) {
                alert("WebGL doesn't support OES_element_index_uint.");
                return null;
            }
        }
        return program;
    }

    init() {
        let dvui_init_return = 0;
        let str = utf8encoder.encode(navigator.platform);
        if (str.length > 0) {
            const ptr = this.allocBuffer(this.instance.exports.gpa_u8, str);
            dvui_init_return = this.instance.exports.dvui_init(ptr, str.length);
            this.instance.exports.gpa_free(ptr, str.length);
        } else {
            dvui_init_return = this.instance.exports.dvui_init(0, 0);
        }

        if (dvui_init_return != 0) {
            throw new Error("ERROR: dvui_init returned " + dvui_init_return);
        }
    }

    requestRender() {
        if (this.stopped) return;

        if (this.renderTimeoutId > 0) {
            clearTimeout(this.renderTimeoutId);
            this.renderTimeoutId = 0;
        }

        if (!this.renderRequested) {
            this.renderRequested = true;
            requestAnimationFrame(this.render.bind(this));
        }
    }

    stop() {
        if (this.renderTimeoutId > 0) {
            clearTimeout(this.renderTimeoutId);
            this.renderTimeoutId = 0;
        }
        this.renderRequested = false;
        this.stopped = true;
    }

    restart() {
        if (!this.stopped) {
            console.log("dvui.restart() called when not stopped");
        }
        this.stopped = false;
        this.requestRender();
    }

    render() {
        if (this.stopped) return;

        this.renderRequested = false;

        const w = this.gl.canvas.clientWidth;
        const h = this.gl.canvas.clientHeight;
        const scale = window.devicePixelRatio;
        this.gl.canvas.width = Math.round(w * scale);
        this.gl.canvas.height = Math.round(h * scale);
        this.renderTargetSize = [
            this.gl.drawingBufferWidth,
            this.gl.drawingBufferHeight,
        ];
        this.gl.viewport(0, 0, this.gl.drawingBufferWidth, this.gl.drawingBufferHeight);
        this.gl.scissor(0, 0, this.gl.drawingBufferWidth, this.gl.drawingBufferHeight);

        this.gl.clearColor(0.0, 0.0, 0.0, 1.0);
        this.gl.clear(this.gl.COLOR_BUFFER_BIT);

        let millis_to_wait = this.instance.exports.dvui_update();
        if (this.need_oskCheck) {
            this.need_oskCheck = false;
            this.oskCheck();
        }

        if (!this.filesCacheModified) {
            this.filesCache.clear();
        }
        this.filesCacheModified = false;

        if (millis_to_wait < 0) {
            this.stop();
        } else if (millis_to_wait == 0) {
            this.requestRender();
        } else if (millis_to_wait > 0) {
            this.renderTimeoutId = setTimeout(
                function() {
                    this.renderTimeoutId = 0;
                    this.requestRender();
                }.bind(this),
                millis_to_wait,
            );
        }
    }

    setCanvas(canvasSelectorOrCanvasElement) {
        const canvas =
            canvasSelectorOrCanvasElement instanceof HTMLCanvasElement
                ? canvasSelectorOrCanvasElement
                : document.querySelector(canvasSelectorOrCanvasElement);

        if (!canvas) {
            alert("Could not find canvas element.");
            return;
        }

        if (!canvas.style.width || !canvas.style.height) {
            console.error(
                "Canvas element does not have defined width and height inline styles",
            );
        }

        if (!this.setupWebGL(canvas)) {
            return;
        }
    }

    run() {
        if (!this.instance) {
            throw new Error(
                "Missing wasm instance, did you forget to call `setInstance`?",
            );
        }
        if (!this.gl) {
            throw new Error(
                "Missing rendering context, did you forget to call `setCanvas`?",
            );
        }
        this.init();

        this.gl.canvas.addEventListener("contextmenu", (ev) => {
            ev.preventDefault();
        });
        window.addEventListener("resize", (ev) => {
            this.requestRender();
        });
        if (this.gl.canvas instanceof HTMLCanvasElement) {
            const resizeObserver = new ResizeObserver(() => {
                this.requestRender();
            });
            resizeObserver.observe(this.gl.canvas);
        }
        this.gl.canvas.addEventListener("mousemove", (ev) => {
            if (this.stopped) return;
            let rect = this.gl.canvas.getBoundingClientRect();
            let x = (ev.clientX - rect.left) / (rect.right - rect.left) *
                this.gl.drawingBufferWidth;
            let y = (ev.clientY - rect.top) / (rect.bottom - rect.top) *
                this.gl.drawingBufferHeight;
            this.instance.exports.add_event(1, 0, 0, x, y);
            this.requestRender();
        });
        this.gl.canvas.addEventListener("mousedown", (ev) => {
            if (this.stopped) return;
            this.instance.exports.add_event(2, ev.button, 0, 0, 0);
            this.requestRender();
        });
        this.gl.canvas.addEventListener("mouseup", (ev) => {
            if (this.stopped) return;
            this.instance.exports.add_event(3, ev.button, 0, 0, 0);
            this.need_oskCheck = true;
            this.requestRender();
        });
        this.gl.canvas.addEventListener("wheel", (ev) => {
            if (this.stopped) return;
            ev.preventDefault();

            // If we haven't gotten a wheel event in a second, reset our first
            // because the user might have switched between mouse and touchpad.
            if ((Date.now() - this.scroll_last_ms) > 1000) {
                this.scroll_lowest_batch = [99999, 99999];
            }
            this.scroll_last_ms = Date.now();

            const touchpad_adj = 0.025;

            if (ev.deltaX != 0) {
                this.scroll_lowest[0] = Math.min(
                    Math.abs(ev.deltaX),
                    this.scroll_lowest[0],
                );
                this.scroll_lowest_batch[0] = Math.min(
                    Math.abs(ev.deltaX),
                    this.scroll_lowest_batch[0],
                );
                var ticks = -ev.deltaX;
                var trackpad = 0;
                if (ev.deltaMode !== 0) {
                    // only mouse wheels produce non-pixel deltas, so this is definitive without
                    // needing the magnitude heuristic.
                    ticks /= this.scroll_lowest_batch[0];
                } else if ((this.scroll_lowest_batch[0] >= 100) || // most wheels
                    (this.scroll_lowest_batch[0] === 16) || // mac firefox
                    (this.scroll_lowest_batch[0] === 9) || // mac firefox holding shift
                    (this.scroll_lowest_batch[0] === 40) || // mac safari/chrome holding shift
                    (this.scroll_lowest_batch[0] === 4.000244140625)) { // mac safari/chrome
                    // assume this is a mouse wheel
                    ticks /= this.scroll_lowest_batch[0];
                    if (this.scroll_lowest_batch[0] === 4.000244140625) {
                        ticks *= touchpad_adj; // mac safari/chrome scale wheel like touchpad
                    }
                    //console.log("wheelX -deltaX " + -ev.deltaX + " ticks " + ticks);
                } else {
                    // assume touchpad
                    trackpad = 1;
                    ticks = ticks / this.scroll_lowest[0] * touchpad_adj;
                    //console.log("touchpadX -deltaX " + -ev.deltaX + " ticks " + ticks);
                }
                this.instance.exports.add_event(
                    4,
                    0,
                    trackpad,
                    ticks,
                    0,
                );
            }
            if (ev.deltaY != 0) {
                //console.log("deltaMode: " + ev.deltaMode + " deltaY: " + ev.deltaY);
                this.scroll_lowest[1] = Math.min(
                    Math.abs(ev.deltaY),
                    this.scroll_lowest[1],
                );
                    Math.abs(ev.deltaY),
                    this.scroll_lowest[1],
                );
                this.scroll_lowest_batch[1] = Math.min(
                    Math.abs(ev.deltaY),
                    this.scroll_lowest_batch[1],
                );
                var ticks = -ev.deltaY;
                var trackpad = 0;
                if (ev.deltaMode !== 0) {
                    // only mouse wheels produce non-pixel deltas
                    ticks /= this.scroll_lowest_batch[1];
                } else if ((this.scroll_lowest_batch[1] >= 100) || // most wheels
                    (this.scroll_lowest_batch[1] === 16) || // mac firefox
                    (this.scroll_lowest_batch[1] === 4.000244140625)) { // mac safari/chrome
                    // assume this is a mouse wheel
                    ticks /= this.scroll_lowest_batch[1];
                    if (this.scroll_lowest_batch[1] === 4.000244140625) {
                        ticks *= touchpad_adj; // mac safari/chrome scale wheel like touchpad
                    }
                    //console.log("wheelY -deltaY " + -ev.deltaY + " ticks " + ticks);
                } else {
                    // assume touchpad
                    trackpad = 1;
                    ticks = ticks / this.scroll_lowest[1] * touchpad_adj;
                    //console.log("touchpadY -deltaY " + -ev.deltaY + " ticks " + ticks);
                }
                this.instance.exports.add_event(
                    4,
                    1,
                    trackpad,
                    ticks,
                    0,
                );
            }
            this.requestRender();
        });

        let keydown = (ev) => {
            if (this.stopped) return;
            if (ev.key == "Tab") {
                if (ev.ctrlKey) return;
                ev.preventDefault();
            }

            let str = utf8encoder.encode(ev.key);
            if (str.length > 0) {
                const ptr = this.allocBuffer(this.instance.exports.arena_u8, str);
                this.instance.exports.add_event(
                    5,
                    ptr,
                    str.length,
                    ev.repeat,
                    encodeModifiers(ev),
                );
                this.requestRender();
            }
        };
        this.gl.canvas.addEventListener("keydown", keydown.bind(this));
        this.hidden_input.addEventListener("keydown", keydown.bind(this));

        let keyup = (ev) => {
            if (this.stopped) return;
            const str = utf8encoder.encode(ev.key);
            const ptr = this.allocBuffer(this.instance.exports.arena_u8, str);
            this.instance.exports.add_event(
                6,
                ptr,
                str.length,
                0,
                encodeModifiers(ev),
            );
            this.need_oskCheck = true;
            this.requestRender();
        };
        this.gl.canvas.addEventListener("keyup", keyup.bind(this));
        this.hidden_input.addEventListener("keyup", keyup.bind(this));

        this.hidden_input.addEventListener("beforeinput", (ev) => {
            if (this.stopped) return;
            ev.preventDefault();
            if (ev.data && !ev.isComposing) {
                const str = utf8encoder.encode(ev.data);
                const ptr = this.allocBuffer(this.instance.exports.arena_u8, str);
                this.instance.exports.add_event(7, ptr, str.length, 0, 0);
                this.requestRender();
            }
        });
        this.hidden_input.addEventListener("compositionend", (ev) => {
            if (this.stopped) return;
            if (ev.data) {
                const str = utf8encoder.encode(ev.data);
                const ptr = this.allocBuffer(this.instance.exports.arena_u8, str);
                this.instance.exports.add_event(7, ptr, str.length, 0, 0);
                this.requestRender();
            }
            ev.target.value = "";
        });
        this.gl.canvas.addEventListener("touchstart", (ev) => {
            if (this.stopped) return;
            ev.preventDefault();
            let rect = this.gl.canvas.getBoundingClientRect();
            for (let i = 0; i < ev.changedTouches.length; i++) {
                let touch = ev.changedTouches[i];
                let x = (touch.clientX - rect.left) /
                    (rect.right - rect.left);
                let y = (touch.clientY - rect.top) /
                    (rect.bottom - rect.top);
                let tidx = touchIndex(this.touches, touch.identifier);
                this.instance.exports.add_event(
                    8,
                    this.touches[tidx][1],
                    0,
                    x,
                    y,
                );
            }
            this.requestRender();
        });
        this.gl.canvas.addEventListener("touchend", (ev) => {
            if (this.stopped) return;
            ev.preventDefault();
            let rect = this.gl.canvas.getBoundingClientRect();
            for (let i = 0; i < ev.changedTouches.length; i++) {
                let touch = ev.changedTouches[i];
                let x = (touch.clientX - rect.left) /
                    (rect.right - rect.left);
                let y = (touch.clientY - rect.top) /
                    (rect.bottom - rect.top);
                let tidx = touchIndex(this.touches, touch.identifier);
                this.instance.exports.add_event(
                    9,
                    this.touches[tidx][1],
                    0,
                    x,
                    y,
                );
                this.touches.splice(tidx, 1);
            }
            this.oskCheck();
            this.requestRender();
        });
        this.gl.canvas.addEventListener("touchmove", (ev) => {
            if (this.stopped) return;
            ev.preventDefault();
            let rect = this.gl.canvas.getBoundingClientRect();
            for (let i = 0; i < ev.changedTouches.length; i++) {
                let touch = ev.changedTouches[i];
                let x = (touch.clientX - rect.left) /
                    (rect.right - rect.left);
                let y = (touch.clientY - rect.top) /
                    (rect.bottom - rect.top);
                let tidx = touchIndex(this.touches, touch.identifier);
                this.instance.exports.add_event(
                    10,
                    this.touches[tidx][1],
                    0,
                    x,
                    y,
                );
            }
            this.requestRender();
        });

        this.requestRender();
    }

    wasm_panic(ptr, len) {
        this.stop();
        const msg = this.stringFromPointer(ptr, len);
        console.error("PANIC:", msg);
        alert(msg);
    }

    wasm_sleep(ms) {
        dvui_sleep(ms);
    }

    wasm_refresh() {
        this.requestRender();
    }

    wasm_pixel_width() {
        return this.gl.drawingBufferWidth;
    }

    wasm_pixel_height() {
        return this.gl.drawingBufferHeight;
    }

    wasm_canvas_width() {
        return this.gl.canvas.clientWidth;
    }

    wasm_canvas_height() {
        return this.gl.canvas.clientHeight;
    }

    wasm_cursor(name_ptr, name_len) {
        const cursor_name = this.stringFromPointer(name_ptr, name_len);
        this.gl.canvas.style.cursor = cursor_name;
    }

    wasm_text_input(x, y, w, h) {
        if (w > 0 && h > 0) {
            this.textInputRect = [x, y, w, h];
        } else {
            this.textInputRect = [];
        }
    }

    wasm_open_url(ptr, len, new_win) {
        const url = this.stringFromPointer(ptr, len);
        if (new_win) {
            window.open(url);
        } else {
            window.location.href = url;
        }
    }

    wasm_preferred_color_scheme() {
        if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
            return 1;
        }
        if (window.matchMedia("(prefers-color-scheme: light)").matches) {
            return 2;
        }
        return 0;
    }

    wasm_prefers_reduced_motion() {
        if (window.matchMedia("(prefers-reduced-motion: no-preference)").matches) {
            return 0;
        }
        if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
            return 1;
        }
        return 0;
    }

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

    wasm_open_file_picker(id, accept_ptr, accept_len, multiple) {
        const accept = this.stringFromPointer(accept_ptr, accept_len);
        dvui_open_file_picker(accept, multiple).then((filelist) => {
            let files = [];
            let data = [];
            for (let i = 0; i < filelist.length; i++) {
                const file = filelist.item(i);
                files.push(file);
                data.push(file.arrayBuffer());
            }
            Promise.all(data).then((data) => {
                this.filesCacheModified = true;
                this.filesCache.set(id, { files, data });
                this.requestRender();
            });
        }).catch(() => {
            console.debug(
                "Filepicker canceled: This is currently not detectable from within dvui",
            );
            this.requestRender();
        });
    }

    wasm_get_file_size(id, file_index) {
        const cached = this.filesCache.get(id);
        if (!cached || cached.files.length <= file_index) return;
        return cached.files[file_index].size;
    }

    wasm_get_file_name(id, file_index) {
        const cached = this.filesCache.get(id);
        if (!cached || cached.files.length <= file_index) return;
        return this.allocStringZ(this.instance.exports.arena_u8, cached.files[file_index].name);
    }

    wasm_read_file_data(id, file_index, data_ptr) {
        const cached = this.filesCache.get(id);
        if (!cached || cached.files.length <= file_index) return;
        var dest = new Uint8Array(this.instance.exports.memory.buffer, data_ptr);
        dest.set(new Uint8Array(cached.data[file_index]));
    }

    wasm_get_number_of_files_available(id) {
        const cached = this.filesCache.get(id);
        if (!cached) return 0;
        return cached.files.length;
    }

    wasm_clipboardTextSet(ptr, len) {
        if (len == 0) {
            return;
        }
        const msg = this.stringFromPointer(ptr, len);
        if (navigator.clipboard) {
            navigator.clipboard.writeText(msg);
        } else {
            this.hidden_input.value = msg;
            this.hidden_input.focus();
            this.hidden_input.select();
            document.execCommand("copy");
            this.hidden_input.value = "";
        }
    }

    wasm_add_noto_font() {
        dvui_fetch("NotoSansKR-Regular.ttf").then((bytes) => {
            const ptr = this.allocBuffer(this.instance.exports.gpa_u8, bytes);
            this.instance.exports.new_font(ptr, bytes.length);
        });
    }
}
