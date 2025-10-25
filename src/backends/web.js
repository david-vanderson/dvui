/**@typedef {BigInt} Id */

/**
 * @param {number} ms Number of milliseconds to sleep
 */
async function dvui_sleep(ms) {
    await new Promise((r) => setTimeout(r, ms));
}

/**
 * @param {string} url
 * @returns {Uint8Array}
 */
async function dvui_fetch(url) {
    let x = await fetch(url);
    let blob = await x.blob();
    //console.log("dvui_fetch: " + blob.size);
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
      vColor = aVertexColor / 255.0;  // normalize u8 colors to 0-1
      vTextureCoord = aTextureCoord;
    }
`;

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
      vColor = aVertexColor / 255.0;  // normalize u8 colors to 0-1
      vTextureCoord = aTextureCoord;
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
        }
        else {
            gl_FragColor = vColor;
        }
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
        }
        else {
            fragColor = vColor;
        }
    }
`;

/**
 * @param {string} canvasId
 * @param {string} wasmFile The url to the wasm file, to be used in `fetch`
 */
function dvui(canvasId, wasmFile) {
    const dvui = new Dvui();
    WebAssembly.instantiateStreaming(fetch(wasmFile), { dvui: dvui.imports })
        .then((result) => {
            dvui.setInstance(result.instance);
            dvui.setCanvas(canvasId);
            dvui.run();
        });
}

const utf8decoder = new TextDecoder();
const utf8encoder = new TextEncoder();

class Dvui {
    /** @type {WebGL2RenderingContext | WebGLRenderingContext} */
    gl;
    /** @type {WebGLBuffer} */
    indexBuffer;
    /** @type {WebGLBuffer} */
    vertexBuffer;
    /** @type {WebGLProgram} */
    shaderProgram;
    /** @type {{ attribLocations: { vertexPosition: number;
            vertexColor: number;
            textureCoord: number;
        };
        uniformLocations: {
            matrix: WebGLUniformLocation | null;
            uSampler: WebGLUniformLocation | null;
            useTex: WebGLUniformLocation | null;
        };
    }} */
    programInfo;
    /** @type {Map<number, [WebGLTexture, number, number]>} */
    textures = new Map();
    newTextureId = 1;
    using_fb = false;
    /** @type {WebGLFramebuffer | null} */
    frame_buffer = null;
    /** @type {[number, number]} */
    renderTargetSize = [0, 0];

    renderRequested = false;
    renderTimeoutId = 0;

    /** @type {WebAssembly.Instance} */
    instance;
    stopped = false;
    console_string = "";
    /** @type {HTMLInputElement} */
    hidden_input;
    /**
     * list of tuple (touch identifier, initial index)
     * @type {[number, number][]} */
    touches = [];
    /** The lowest data seen, used to determine the delta for one "tick"
     * of the scroll wheel
     *
     * The first number is x and second is y
     * @type {[number, number]} */
    lowest_scroll_delta = [99999, 99999];
    /**
     * x y w h of on screen keyboard editing position, or empty if none
     *
     * @type {[number, number, number, number] | []} */
    textInputRect = [];
    need_oskCheck = false;

    // Used for file uploads. Only valid for one frame
    filesCacheModified = false;
    /** @type {Map<Id, FileList>} */
    filesCache = new Map();

    //let par = document.createElement("p");
    //document.body.prepend(par);

    get webgl2() {
        return this.gl instanceof WebGL2RenderingContext;
    }

    oskCheck() {
        if (this.textInputRect.length == 0) {
            this.gl.canvas.focus();
        } else {
            const rect = this.gl.canvas.getBoundingClientRect();
            const left = window.scrollX + rect.left + this.textInputRect[0];
            const top = window.scrollY + rect.top + this.textInputRect[1];
            // limit the width and height to prevent overflow
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
            //par.textContent = hidden_input.style.left + " " + hidden_input.style.top + " " + hidden_input.style.width + " " + hidden_input.style.height;
        }
    }

    touchIndex(pointerId) {
        let idx = this.touches.findIndex((e) => e[0] === pointerId);
        if (idx < 0) {
            idx = this.touches.length;
            this.touches.push([pointerId, idx]);
        }

        return idx;
    }

    constructor() {
        this.hidden_input = document.createElement("input");
        this.hidden_input.setAttribute("autocapitalize", "none");
        this.hidden_input.style.position = "absolute";
        this.hidden_input.style.left = 0;
        this.hidden_input.style.top = 0;
        // remove extra size so input doesn't cause overflow
        this.hidden_input.style.padding = 0;
        this.hidden_input.style.border = 0;
        this.hidden_input.style.margin = 0;
        this.hidden_input.style.opacity = 0;
        this.hidden_input.style.zIndex = -1;
        document.body.prepend(this.hidden_input);

        this.imports = {
            wasm_about_webgl2: () => {
                if (this.webgl2) {
                    return 1;
                } else {
                    return 0;
                }
            },
            wasm_panic: (ptr, len) => {
                this.stopped = true;
                let msg = utf8decoder.decode(
                    new Uint8Array(
                        this.instance.exports.memory.buffer,
                        ptr,
                        len,
                    ),
                );
                console.error("PANIC:", msg);
                alert(msg);
            },
            wasm_console_drain: (ptr, len) => {
                this.console_string += utf8decoder.decode(
                    new Uint8Array(
                        this.instance.exports.memory.buffer,
                        ptr,
                        len,
                    ),
                );
            },
            wasm_console_flush: (level) => {
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
            },
            wasm_now: () => {
                return performance.now();
            },
            wasm_sleep: (ms) => {
                dvui_sleep(ms);
            },
            wasm_refresh: () => {
                this.requestRender();
            },
            wasm_pixel_width: () => {
                return this.gl.drawingBufferWidth;
            },
            wasm_pixel_height: () => {
                return this.gl.drawingBufferHeight;
            },
            wasm_frame_buffer: () => {
                if (this.using_fb) {
                    return 1;
                } else {
                    return 0;
                }
            },
            wasm_canvas_width: () => {
                return this.gl.canvas.clientWidth;
            },
            wasm_canvas_height: () => {
                return this.gl.canvas.clientHeight;
            },
            wasm_textureCreate: (pixels, width, height, interp) => {
                const pixelData = new Uint8Array(
                    this.instance.exports.memory.buffer,
                    pixels,
                    width * height * 4,
                );

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
                this.gl.texParameteri(
                    this.gl.TEXTURE_2D,
                    this.gl.TEXTURE_WRAP_S,
                    this.gl.CLAMP_TO_EDGE,
                );
                this.gl.texParameteri(
                    this.gl.TEXTURE_2D,
                    this.gl.TEXTURE_WRAP_T,
                    this.gl.CLAMP_TO_EDGE,
                );

                this.gl.bindTexture(this.gl.TEXTURE_2D, null);

                return id;
            },
            wasm_textureCreateTarget: (width, height, interp) => {
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
                this.gl.texParameteri(
                    this.gl.TEXTURE_2D,
                    this.gl.TEXTURE_WRAP_S,
                    this.gl.CLAMP_TO_EDGE,
                );
                this.gl.texParameteri(
                    this.gl.TEXTURE_2D,
                    this.gl.TEXTURE_WRAP_T,
                    this.gl.CLAMP_TO_EDGE,
                );

                this.gl.bindTexture(this.gl.TEXTURE_2D, null);

                return id;
            },
            wasm_textureRead: (textureId, pixels_out, width, height) => {
                //console.log("textureRead " + textureId);
                const texture = this.textures.get(textureId)[0];

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

                var dest = new Uint8Array(
                    this.instance.exports.memory.buffer,
                    pixels_out,
                    width * height * 4,
                );
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
            },
            wasm_renderTarget: (id) => {
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

                    this.gl.framebufferTexture2D(
                        this.gl.FRAMEBUFFER,
                        this.gl.COLOR_ATTACHMENT0,
                        this.gl.TEXTURE_2D,
                        this.textures.get(id)[0],
                        0,
                    );
                    this.renderTargetSize = [
                        this.textures.get(id)[1],
                        this.textures.get(id)[2],
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
                }
            },
            wasm_textureDestroy: (id) => {
                //console.log("deleting texture " + id);
                const texture = this.textures.get(id)[0];
                this.textures.delete(id);

                this.gl.deleteTexture(texture);
            },
            wasm_renderGeometry: (
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
            ) => {
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
                    this.gl.STATIC_DRAW,
                );

                this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.vertexBuffer);
                const vertexes = new Uint8Array(
                    this.instance.exports.memory.buffer,
                    vertex_ptr,
                    vertex_len,
                );
                this.gl.bufferData(
                    this.gl.ARRAY_BUFFER,
                    vertexes,
                    this.gl.STATIC_DRAW,
                );

                let matrix = new Float32Array(16);
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
                    this.gl.activeTexture(this.gl.TEXTURE0);
                    this.gl.bindTexture(
                        this.gl.TEXTURE_2D,
                        this.textures.get(textureId)[0],
                    );
                    this.gl.uniform1i(
                        this.programInfo.uniformLocations.useTex,
                        1,
                    );
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
            },
            wasm_cursor: (name_ptr, name_len) => {
                let cursor_name = utf8decoder.decode(
                    new Uint8Array(
                        this.instance.exports.memory.buffer,
                        name_ptr,
                        name_len,
                    ),
                );
                this.gl.canvas.style.cursor = cursor_name;
            },
            wasm_text_input: (x, y, w, h) => {
                if (w > 0 && h > 0) {
                    this.textInputRect = [x, y, w, h];
                } else {
                    this.textInputRect = [];
                }
            },
            wasm_open_url: (ptr, len, new_win) => {
                let url = utf8decoder.decode(
                    new Uint8Array(
                        this.instance.exports.memory.buffer,
                        ptr,
                        len,
                    ),
                );

                if (new_win) {
                    window.open(url);
                } else {
                    window.location.href = url;
                }
            },
            wasm_preferred_color_scheme: () => {
                if (
                    window.matchMedia("(prefers-color-scheme: dark)").matches
                ) {
                    return 1;
                }
                if (
                    window.matchMedia("(prefers-color-scheme: light)").matches
                ) {
                    return 2;
                }
                return 0;
            },
            wasm_download_data: (
                name_ptr,
                name_len,
                data_ptr,
                data_len,
            ) => {
                const name = utf8decoder.decode(
                    new Uint8Array(
                        this.instance.exports.memory.buffer,
                        name_ptr,
                        name_len,
                    ),
                );
                const data = new Uint8Array(
                    this.instance.exports.memory.buffer,
                    data_ptr,
                    data_len,
                );
                const blob = new Blob([data], { type: "octet/stream" });
                const fileURL = URL.createObjectURL(blob);
                const dl = document.createElement("a");
                dl.href = fileURL;
                dl.download = name;
                document.body.appendChild(dl);
                dl.click();
                document.body.removeChild(dl);
                URL.revokeObjectURL(fileURL);
            },
            wasm_open_file_picker: (id, accept_ptr, accept_len, multiple) => {
                let accept = utf8decoder.decode(
                    new Uint8Array(
                        this.instance.exports.memory.buffer,
                        accept_ptr,
                        accept_len,
                    ),
                );
                // console.log("Open picker", accept_ptr, accept_len, accept, multiple);
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
            },
            wasm_get_file_size: (id, file_index) => {
                const cached = this.filesCache.get(id);
                if (!cached || cached.files.length <= file_index) return;
                const size = cached.files[file_index].size;
                return size;
            },
            wasm_get_file_name: (id, file_index) => {
                const cached = this.filesCache.get(id);
                if (!cached || cached.files.length <= file_index) return;
                const name = utf8encoder.encode(
                    cached.files[file_index].name,
                );
                const ptr = this.instance.exports.arena_u8(
                    name.length + 1,
                );
                var dest = new Uint8Array(
                    this.instance.exports.memory.buffer,
                    ptr,
                    name.length + 1,
                );
                dest.set(name);
                dest.set([0], name.length);
                return ptr;
            },
            wasm_read_file_data: (id, file_index, data_ptr) => {
                const cached = this.filesCache.get(id);
                if (!cached || cached.files.length <= file_index) return;
                var dest = new Uint8Array(
                    this.instance.exports.memory.buffer,
                    data_ptr,
                );
                dest.set(new Uint8Array(cached.data[file_index]));
            },
            wasm_get_number_of_files_available: (id) => {
                const cached = this.filesCache.get(id);
                if (!cached) return 0;
                return cached.files.length;
            },
            wasm_clipboardTextSet: (ptr, len) => {
                if (len == 0) {
                    return;
                }

                let msg = utf8decoder.decode(
                    new Uint8Array(
                        this.instance.exports.memory.buffer,
                        ptr,
                        len,
                    ),
                );
                if (navigator.clipboard) {
                    navigator.clipboard.writeText(msg);
                } else {
                    this.hidden_input.value = msg;
                    this.hidden_input.focus();
                    this.hidden_input.select();
                    document.execCommand("copy");
                    this.hidden_input.value = "";
                }
            },
            wasm_add_noto_font: () => {
                dvui_fetch("NotoSansKR-Regular.ttf").then((bytes) => {
                    //console.log("bytes len " + bytes.length);
                    const ptr = this.instance.exports.gpa_u8(
                        bytes.length,
                    );
                    var dest = new Uint8Array(
                        this.instance.exports.memory.buffer,
                        ptr,
                        bytes.length,
                    );
                    dest.set(bytes);
                    this.instance.exports.new_font(
                        ptr,
                        bytes.length,
                    );
                });
            },
        };
    }

    setInstance(instance) {
        this.instance = instance;
    }

    setCanvas(canvasSelectorOrCanvasElement) {
        /** @type {HTMLCanvasElement | null} */
        const canvas =
            canvasSelectorOrCanvasElement instanceof HTMLCanvasElement
                ? canvasSelectorOrCanvasElement
                : document.querySelector(canvasSelectorOrCanvasElement);

        if (!canvas) {
            alert("Could not find canvas element.");
            return;
        }

        if (!canvas.style.width || !canvas.style.height) {
            // Needed so that the canvas element can scale and report its size correctly.
            // Absolute and relative length are both valid. Setting both to 100% is
            // probably what you want.
            console.error(
                "Canvas element does not have defined width and height inline styles",
            );
        }

        this.gl = canvas.getContext("webgl2", { alpha: true });
        if (this.gl === null) {
            this.gl = canvas.getContext("webgl", { alpha: true });
        }

        if (this.gl === null) {
            alert("Unable to initialize WebGL.");
            return;
        }

        if (!this.webgl2) {
            const ext = this.gl.getExtension("OES_element_index_uint");
            if (ext === null) {
                alert("WebGL doesn't support OES_element_index_uint.");
                return;
            }
        }
        this.frame_buffer = this.gl.createFramebuffer();

        const vertexShader = this.gl.createShader(this.gl.VERTEX_SHADER);
        if (this.webgl2) {
            this.gl.shaderSource(vertexShader, vertexShaderSource_webgl2);
        } else {
            this.gl.shaderSource(vertexShader, vertexShaderSource_webgl);
        }
        this.gl.compileShader(vertexShader);
        if (!this.gl.getShaderParameter(vertexShader, this.gl.COMPILE_STATUS)) {
            alert(
                `Error compiling vertex shader: ${
                    this.gl.getShaderInfoLog(vertexShader)
                }`,
            );
            this.gl.deleteShader(vertexShader);
            return null;
        }

        const fragmentShader = this.gl.createShader(this.gl.FRAGMENT_SHADER);
        if (this.webgl2) {
            this.gl.shaderSource(fragmentShader, fragmentShaderSource_webgl2);
        } else {
            this.gl.shaderSource(fragmentShader, fragmentShaderSource_webgl);
        }
        this.gl.compileShader(fragmentShader);
        if (
            !this.gl.getShaderParameter(fragmentShader, this.gl.COMPILE_STATUS)
        ) {
            alert(
                `Error compiling fragment shader: ${
                    this.gl.getShaderInfoLog(fragmentShader)
                }`,
            );
            this.gl.deleteShader(fragmentShader);
            return null;
        }

        this.shaderProgram = this.gl.createProgram();
        this.gl.attachShader(this.shaderProgram, vertexShader);
        this.gl.attachShader(this.shaderProgram, fragmentShader);
        this.gl.linkProgram(this.shaderProgram);

        if (
            !this.gl.getProgramParameter(
                this.shaderProgram,
                this.gl.LINK_STATUS,
            )
        ) {
            alert(
                `Error initializing shader program: ${
                    this.gl.getProgramInfoLog(this.shaderProgram)
                }`,
            );
            return null;
        }

        this.programInfo = {
            attribLocations: {
                vertexPosition: this.gl.getAttribLocation(
                    this.shaderProgram,
                    "aVertexPosition",
                ),
                vertexColor: this.gl.getAttribLocation(
                    this.shaderProgram,
                    "aVertexColor",
                ),
                textureCoord: this.gl.getAttribLocation(
                    this.shaderProgram,
                    "aTextureCoord",
                ),
            },
            uniformLocations: {
                matrix: this.gl.getUniformLocation(
                    this.shaderProgram,
                    "uMatrix",
                ),
                uSampler: this.gl.getUniformLocation(
                    this.shaderProgram,
                    "uSampler",
                ),
                useTex: this.gl.getUniformLocation(
                    this.shaderProgram,
                    "useTex",
                ),
            },
        };

        this.indexBuffer = this.gl.createBuffer();
        this.vertexBuffer = this.gl.createBuffer();

        this.gl.enable(this.gl.BLEND);
        this.gl.blendFunc(this.gl.ONE, this.gl.ONE_MINUS_SRC_ALPHA);
        this.gl.enable(this.gl.SCISSOR_TEST);
        this.gl.scissor(
            0,
            0,
            this.gl.canvas.clientWidth,
            this.gl.canvas.clientHeight,
        );
    }

    init() {
        let dvui_init_return = 0;
        let str = utf8encoder.encode(navigator.platform);
        if (str.length > 0) {
            const ptr = this.instance.exports.gpa_u8(
                str.length,
            );
            var dest = new Uint8Array(
                this.instance.exports.memory.buffer,
                ptr,
                str.length,
            );
            dest.set(str);
            dvui_init_return = this.instance.exports.dvui_init(
                ptr,
                str.length,
            );
            this.instance.exports.gpa_free(ptr, str.length);
        } else {
            dvui_init_return = this.instance.exports.dvui_init(
                0,
                0,
            );
        }

        if (dvui_init_return != 0) {
            throw new Error("ERROR: dvui_init returned " + dvui_init_return);
        }
    }

    requestRender() {
        if (this.renderTimeoutId > 0) {
            // we got called before the timeout happened
            clearTimeout(this.renderTimeoutId);
            this.renderTimeoutId = 0;
        }

        if (!this.renderRequested) {
            // multiple events could call requestRender multiple times, and
            // we only want a single requestAnimationFrame to happen before
            // each call to dvui_update
            this.renderRequested = true;
            requestAnimationFrame(this.render.bind(this));
        }
    }

    render() {
        if (this.stopped) return;
        this.renderRequested = false;

        // if the canvas changed size, adjust the backing buffer
        const w = this.gl.canvas.clientWidth;
        const h = this.gl.canvas.clientHeight;
        const scale = window.devicePixelRatio;
        //console.log("wxh " + w + "x" + h + " scale " + scale);
        this.gl.canvas.width = Math.round(w * scale);
        this.gl.canvas.height = Math.round(h * scale);
        this.renderTargetSize = [
            this.gl.drawingBufferWidth,
            this.gl.drawingBufferHeight,
        ];
        this.gl.viewport(
            0,
            0,
            this.gl.drawingBufferWidth,
            this.gl.drawingBufferHeight,
        );
        this.gl.scissor(
            0,
            0,
            this.gl.drawingBufferWidth,
            this.gl.drawingBufferHeight,
        );

        this.gl.clearColor(0.0, 0.0, 0.0, 1.0); // Clear to black, fully opaque
        this.gl.clear(this.gl.COLOR_BUFFER_BIT);

        let millis_to_wait = this.instance.exports.dvui_update();
        if (this.need_oskCheck) {
            this.need_oskCheck = false;
            this.oskCheck();
        }

        if (!this.filesCacheModified) {
            // Only clear if we didn't add anything this frame. Async could add items after they were requested
            // in the frame, so keep if for two frames
            this.filesCache.clear();
        }
        this.filesCacheModified = false;

        if (millis_to_wait < 0) {
            this.stopped = true;
        } else if (millis_to_wait == 0) {
            this.requestRender();
        } else if (millis_to_wait > 0) {
            this.renderTimeoutId = setTimeout(
                function () {
                    this.renderTimeoutId = 0;
                    this.requestRender();
                }.bind(this),
                millis_to_wait,
            );
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

        // event listeners
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
            let rect = this.gl.canvas.getBoundingClientRect();
            let x = (ev.clientX - rect.left) / (rect.right - rect.left) *
                this.gl.drawingBufferWidth;
            let y = (ev.clientY - rect.top) / (rect.bottom - rect.top) *
                this.gl.drawingBufferHeight;
            this.instance.exports.add_event(1, 0, 0, x, y);
            this.requestRender();
        });
        this.gl.canvas.addEventListener("mousedown", (ev) => {
            this.instance.exports.add_event(2, ev.button, 0, 0, 0);
            this.requestRender();
        });
        this.gl.canvas.addEventListener("mouseup", (ev) => {
            this.instance.exports.add_event(3, ev.button, 0, 0, 0);
            this.need_oskCheck = true;
            this.requestRender();
        });
        this.gl.canvas.addEventListener("wheel", (ev) => {
            ev.preventDefault();
            if (ev.deltaX != 0) {
                const min = Math.min(
                    Math.abs(ev.deltaX),
                    this.lowest_scroll_delta[0],
                );
                this.lowest_scroll_delta[0] = min;
                this.instance.exports.add_event(
                    4,
                    0,
                    0,
                    ev.deltaX / min,
                    0,
                );
            }
            if (ev.deltaY != 0) {
                const min = Math.min(
                    Math.abs(ev.deltaY),
                    this.lowest_scroll_delta[1],
                );
                this.lowest_scroll_delta[1] = min;
                this.instance.exports.add_event(
                    4,
                    1,
                    0,
                    -ev.deltaY / min,
                    0,
                );
            }
            this.requestRender();
        });

        let keydown = (ev) => {
            if (ev.key == "Tab") {
                // stop tab from tabbing away from the canvas
                ev.preventDefault();
            }

            let str = utf8encoder.encode(ev.key);
            if (str.length > 0) {
                const ptr = this.instance.exports.arena_u8(
                    str.length,
                );
                var dest = new Uint8Array(
                    this.instance.exports.memory.buffer,
                    ptr,
                    str.length,
                );
                dest.set(str);
                this.instance.exports.add_event(
                    5,
                    ptr,
                    str.length,
                    ev.repeat,
                    (ev.metaKey << 3) + (ev.altKey << 2) +
                        (ev.ctrlKey << 1) + (ev.shiftKey << 0),
                );
                this.requestRender();
            }
        };
        this.gl.canvas.addEventListener("keydown", keydown.bind(this));
        this.hidden_input.addEventListener("keydown", keydown.bind(this));

        let keyup = (ev) => {
            const str = utf8encoder.encode(ev.key);
            const ptr = this.instance.exports.arena_u8(str.length);
            var dest = new Uint8Array(
                this.instance.exports.memory.buffer,
                ptr,
                str.length,
            );
            dest.set(str);
            this.instance.exports.add_event(
                6,
                ptr,
                str.length,
                0,
                (ev.metaKey << 3) + (ev.altKey << 2) + (ev.ctrlKey << 1) +
                    (ev.shiftKey << 0),
            );
            this.need_oskCheck = true;
            this.requestRender();
        };
        this.gl.canvas.addEventListener("keyup", keyup.bind(this));
        this.hidden_input.addEventListener("keyup", keyup.bind(this));

        this.hidden_input.addEventListener("beforeinput", (ev) => {
            ev.preventDefault();
            if (ev.data && !ev.isComposing) {
                const str = utf8encoder.encode(ev.data);
                const ptr = this.instance.exports.arena_u8(
                    str.length,
                );
                var dest = new Uint8Array(
                    this.instance.exports.memory.buffer,
                    ptr,
                    str.length,
                );
                dest.set(str);
                this.instance.exports.add_event(
                    7,
                    ptr,
                    str.length,
                    0,
                    0,
                );
                this.requestRender();
            }
        });
        this.hidden_input.addEventListener("compositionend", (ev) => {
            if (ev.data) {
                const str = utf8encoder.encode(ev.data);
                const ptr = this.instance.exports.arena_u8(
                    str.length,
                );
                var dest = new Uint8Array(
                    this.instance.exports.memory.buffer,
                    ptr,
                    str.length,
                );
                dest.set(str);
                this.instance.exports.add_event(
                    7,
                    ptr,
                    str.length,
                    0,
                    0,
                );
                this.requestRender();
            }
            // Reset value to empty after composition maybe put text there
            ev.target.value = "";
        });
        this.gl.canvas.addEventListener("touchstart", (ev) => {
            ev.preventDefault();
            let rect = this.gl.canvas.getBoundingClientRect();
            for (let i = 0; i < ev.changedTouches.length; i++) {
                let touch = ev.changedTouches[i];
                let x = (touch.clientX - rect.left) /
                    (rect.right - rect.left);
                let y = (touch.clientY - rect.top) /
                    (rect.bottom - rect.top);
                let tidx = this.touchIndex(touch.identifier);
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
            ev.preventDefault();
            let rect = this.gl.canvas.getBoundingClientRect();
            for (let i = 0; i < ev.changedTouches.length; i++) {
                let touch = ev.changedTouches[i];
                let x = (touch.clientX - rect.left) /
                    (rect.right - rect.left);
                let y = (touch.clientY - rect.top) /
                    (rect.bottom - rect.top);
                let tidx = this.touchIndex(touch.identifier);
                this.instance.exports.add_event(
                    9,
                    this.touches[tidx][1],
                    0,
                    x,
                    y,
                );
                this.touches.splice(tidx, 1);
            }
            // Osk has to be done within the event handler so that on-screen keyboard can show
            // https://stackoverflow.com/a/6837575
            this.oskCheck();
            this.requestRender();
        });
        this.gl.canvas.addEventListener("touchmove", (ev) => {
            ev.preventDefault();
            let rect = this.gl.canvas.getBoundingClientRect();
            for (let i = 0; i < ev.changedTouches.length; i++) {
                let touch = ev.changedTouches[i];
                let x = (touch.clientX - rect.left) /
                    (rect.right - rect.left);
                let y = (touch.clientY - rect.top) /
                    (rect.bottom - rect.top);
                let tidx = this.touchIndex(touch.identifier);
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
        //canvas.addEventListener("touchcancel", (ev) => {
        //    console.log(ev);
        //    this.requestRender();
        //});

        // start the first update
        this.requestRender();
    }
}
