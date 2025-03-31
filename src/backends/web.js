const Dvui = class {

    constructor() {
        this.webgl2 = true;
        this.gl = null;
        this.indexBuffer = null;
        this.vertexBuffer = null;
        this.shaderProgram = null;
        this.textures = new Map();
        this.newTextureId = 1;
        this.using_fb = false;
        this.frame_buffer = null;
        this.renderTargetSize = [0, 0];
        this.wasmResult = null;
        this.log_string = '';
        this.hidden_input = null;
        this.touches = [];  // list of tuple (touch identifier, initial index)
        this.textInputRect = [];  // x y w h of on screen keyboard editing position, or empty if none
        this.utf8decoder = new TextDecoder();
        this.utf8encoder = new TextEncoder();

    }

    async dvui_sleep(ms) {
        await new Promise(r => setTimeout(r, ms));
    }

    async dvui_fetch(url) {
        let x = await fetch(url);
        let blob = await x.blob();
        //console.log("dvui_fetch: " + blob.size);
        return new Uint8Array(await blob.arrayBuffer());
    }

    imports() {
        let self = this;
        return {
            env: {
                wasm_about_webgl2: () => {
                    if (self.webgl2) {
                        return 1;
                    } else {
                        return 0;
                    }
                },
                wasm_panic: (ptr, len) => {
                    let msg = self.utf8decoder.decode(new Uint8Array(self.wasmResult.instance.exports.memory.buffer, ptr, len));
                    alert(msg);
                    throw Error(msg);
                },
                wasm_log_write: (ptr, len) => {
                    self.log_string += self.utf8decoder.decode(new Uint8Array(self.wasmResult.instance.exports.memory.buffer, ptr, len));
                },
                wasm_log_flush: () => {
                    console.log(self.log_string);
                    self.log_string = '';
                },
                wasm_now() {
                    return performance.now();
                },
                wasm_sleep(ms) {
                    self.dvui_sleep(ms);
                },
                wasm_pixel_width() {
                    return self.gl.drawingBufferWidth;
                },
                wasm_pixel_height() {
                    return self.gl.drawingBufferHeight;
                },
                wasm_frame_buffer() {
                    if (self.using_fb)
                        return 1;
                    else
                        return 0;
                },
                wasm_canvas_width() {
                    return self.gl.canvas.clientWidth;
                },
                wasm_canvas_height() {
                    return self.gl.canvas.clientHeight;
                },
                wasm_textureCreate(pixels, width, height, interp) {
                    const pixelData = new Uint8Array(self.wasmResult.instance.exports.memory.buffer, pixels, width * height * 4);

                    const texture = self.gl.createTexture();
                    const id = self.newTextureId;
                    //console.log("creating texture " + id);
                    self.newTextureId += 1;
                    self.textures.set(id, [texture, width, height]);
                    self.gl.bindTexture(self.gl.TEXTURE_2D, texture);

                    self.gl.texImage2D(
                        self.gl.TEXTURE_2D,
                        0,
                        self.gl.RGBA,
                        width,
                        height,
                        0,
                        self.gl.RGBA,
                        self.gl.UNSIGNED_BYTE,
                        pixelData,
                    );

                    if (self.webgl2) {
                        self.gl.generateMipmap(self.gl.TEXTURE_2D);
                    }

                    if (interp == 0) {
                        self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_MIN_FILTER, self.gl.NEAREST);
                        self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_MAG_FILTER, self.gl.NEAREST);
                    } else {
                        self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_MIN_FILTER, self.gl.LINEAR);
                        self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_MAG_FILTER, self.gl.LINEAR);
                    }
                    self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_WRAP_S, self.gl.CLAMP_TO_EDGE);
                    self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_WRAP_T, self.gl.CLAMP_TO_EDGE);

                    self.gl.bindTexture(self.gl.TEXTURE_2D, null);

                    return id;
                },
                wasm_textureCreateTarget(width, height, interp) {
                    const texture = self.gl.createTexture();
                    const id = self.newTextureId;
                    //console.log("creating texture " + id);
                    self.newTextureId += 1;
                    self.textures.set(id, [texture, width, height]);
                    self.gl.bindTexture(self.gl.TEXTURE_2D, texture);

                    self.gl.texImage2D(
                        self.gl.TEXTURE_2D,
                        0,
                        self.gl.RGBA,
                        width,
                        height,
                        0,
                        self.gl.RGBA,
                        self.gl.UNSIGNED_BYTE,
                        null,
                    );

                    if (interp == 0) {
                        self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_MIN_FILTER, self.gl.NEAREST);
                        self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_MAG_FILTER, self.gl.NEAREST);
                    } else {
                        self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_MIN_FILTER, self.gl.LINEAR);
                        self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_MAG_FILTER, self.gl.LINEAR);
                    }
                    self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_WRAP_S, self.gl.CLAMP_TO_EDGE);
                    self.gl.texParameteri(self.gl.TEXTURE_2D, self.gl.TEXTURE_WRAP_T, self.gl.CLAMP_TO_EDGE);

                    self.gl.bindTexture(self.gl.TEXTURE_2D, null);

                    return id;
                },
                wasm_textureRead(textureId, pixels_out, width, height) {
                    //console.log("textureRead " + textureId);
                    const texture = self.textures.get(textureId)[0];

                    self.gl.bindFramebuffer(self.gl.FRAMEBUFFER, self.frame_buffer);
                    self.gl.framebufferTexture2D(self.gl.FRAMEBUFFER, self.gl.COLOR_ATTACHMENT0, self.gl.TEXTURE_2D, texture, 0);

                    var dest = new Uint8Array(self.wasmResult.instance.exports.memory.buffer, pixels_out, width * height * 4);
                    self.gl.readPixels(0, 0, width, height, self.gl.RGBA, self.gl.UNSIGNED_BYTE, dest, 0);

                    self.gl.bindFramebuffer(self.gl.FRAMEBUFFER, null);
                },
                wasm_renderTarget(id) {
                    //console.log("renderTarget " + id);
                    if (id === 0) {
                        self.using_fb = false;
                        self.gl.bindFramebuffer(self.gl.FRAMEBUFFER, null);
                        self.renderTargetSize = [self.gl.drawingBufferWidth, self.gl.drawingBufferHeight];
                        self.gl.viewport(0, 0, self.renderTargetSize[0], self.renderTargetSize[1]);
                        self.gl.scissor(0, 0, self.renderTargetSize[0], self.renderTargetSize[1]);
                    } else {
                        self.using_fb = true;
                        self.gl.bindFramebuffer(self.gl.FRAMEBUFFER, self.frame_buffer);

                        self.gl.framebufferTexture2D(self.gl.FRAMEBUFFER, self.gl.COLOR_ATTACHMENT0, self.gl.TEXTURE_2D, self.textures.get(id)[0], 0);
                        self.renderTargetSize = [self.textures.get(id)[1], self.textures.get(id)[2]];
                        self.gl.viewport(0, 0, self.renderTargetSize[0], self.renderTargetSize[1]);
                        self.gl.scissor(0, 0, self.renderTargetSize[0], self.renderTargetSize[1]);
                    }
                },
                wasm_textureDestroy(id) {
                    //console.log("deleting texture " + id);
                    const texture = self.textures.get(id)[0];
                    self.textures.delete(id);

                    self.gl.deleteTexture(texture);
                },
                wasm_renderGeometry(textureId, index_ptr, index_len, vertex_ptr, vertex_len, sizeof_vertex, offset_pos, offset_col, offset_uv, clip, x, y, w, h) {
                    //console.log("drawClippedTriangles " + textureId + " sizeof " + sizeof_vertex + " pos " + offset_pos + " col " + offset_col + " uv " + offset_uv);

                    //let old_scissor;
                    if (clip === 1) {
                        // just calling getParameter here is quite slow (5-10 ms per frame according to chrome)
                        //old_scissor = self.gl.getParameter(self.gl.SCISSOR_BOX);
                        self.gl.scissor(x, y, w, h);
                    }

                    self.gl.bindBuffer(self.gl.ELEMENT_ARRAY_BUFFER, self.indexBuffer);
                    const indices = new Uint16Array(self.wasmResult.instance.exports.memory.buffer, index_ptr, index_len / 2);
                    self.gl.bufferData( self.gl.ELEMENT_ARRAY_BUFFER, indices, self.gl.STATIC_DRAW);

                    self.gl.bindBuffer(self.gl.ARRAY_BUFFER, self.vertexBuffer);
                    const vertexes = new Uint8Array(self.wasmResult.instance.exports.memory.buffer, vertex_ptr, vertex_len);
                    self.gl.bufferData( self.gl.ARRAY_BUFFER, vertexes, self.gl.STATIC_DRAW);

                    let matrix = new Float32Array(16);
                    matrix[0] = 2.0 / self.renderTargetSize[0];
                    matrix[1] = 0.0;
                    matrix[2] = 0.0;
                    matrix[3] = 0.0;
                    matrix[4] = 0.0;
                    if (self.using_fb) {
                        matrix[5] = 2.0 / self.renderTargetSize[1];
                    } else {
                        matrix[5] = -2.0 / self.renderTargetSize[1];
                    }
                    matrix[6] = 0.0;
                    matrix[7] = 0.0;
                    matrix[8] = 0.0;
                    matrix[9] = 0.0;
                    matrix[10] = 1.0;
                    matrix[11] = 0.0;
                    matrix[12] = -1.0;
                    if (self.using_fb) {
                        matrix[13] = -1.0;
                    } else {
                        matrix[13] = 1.0;
                    }
                    matrix[14] = 0.0;
                    matrix[15] = 1.0;

                    // vertex
                    self.gl.bindBuffer(self.gl.ARRAY_BUFFER, self.vertexBuffer);
                    self.gl.vertexAttribPointer(
                        self.programInfo.attribLocations.vertexPosition,
                        2,  // num components
                        self.gl.FLOAT,
                        false,  // don't normalize
                        sizeof_vertex,  // stride
                        offset_pos,  // offset
                    );
                    self.gl.enableVertexAttribArray(self.programInfo.attribLocations.vertexPosition);

                    // color
                    self.gl.bindBuffer(self.gl.ARRAY_BUFFER, self.vertexBuffer);
                    self.gl.vertexAttribPointer(
                        self.programInfo.attribLocations.vertexColor,
                        4,  // num components
                        self.gl.UNSIGNED_BYTE,
                        false,  // don't normalize
                        sizeof_vertex, // stride
                        offset_col,  // offset
                    );
                    self.gl.enableVertexAttribArray(self.programInfo.attribLocations.vertexColor);

                    // texture
                    self.gl.bindBuffer(self.gl.ARRAY_BUFFER, self.vertexBuffer);
                    self.gl.vertexAttribPointer(
                        self.programInfo.attribLocations.textureCoord,
                        2,  // num components
                        self.gl.FLOAT,
                        false,  // don't normalize
                        sizeof_vertex, // stride
                        offset_uv,  // offset
                    );
                    self.gl.enableVertexAttribArray(self.programInfo.attribLocations.textureCoord);

                    // Tell WebGL to use our program when drawing
                    self.gl.useProgram(self.shaderProgram);

                    // Set the shader uniforms
                    self.gl.uniformMatrix4fv(
                        self.programInfo.uniformLocations.matrix,
                        false,
                        matrix,
                    );

                    if (textureId != 0) {
                        self.gl.activeTexture(self.gl.TEXTURE0);
                        self.gl.bindTexture(self.gl.TEXTURE_2D, self.textures.get(textureId)[0]);
                        self.gl.uniform1i(self.programInfo.uniformLocations.useTex, 1);
                    } else {
                        self.gl.bindTexture(self.gl.TEXTURE_2D, null);
                        self.gl.uniform1i(self.programInfo.uniformLocations.useTex, 0);
                    }

                    self.gl.uniform1i(self.programInfo.uniformLocations.uSampler, 0);

                    //console.log("drawElements " + textureId);
                    self.gl.drawElements(self.gl.TRIANGLES, indices.length, self.gl.UNSIGNED_SHORT, 0);

                    if (clip === 1) {
                        //self.gl.scissor(old_scissor[0], old_scissor[1], old_scissor[2], old_scissor[3]);
                        self.gl.scissor(0, 0, self.renderTargetSize[0], self.renderTargetSize[1]);
                    }
                },
                wasm_cursor(name_ptr, name_len) {
                    let cursor_name = self.utf8decoder.decode(new Uint8Array(self.wasmResult.instance.exports.memory.buffer, name_ptr, name_len));
                    self.gl.canvas.style.cursor = cursor_name;
                },
                wasm_text_input(x, y, w, h) {
                    if (w > 0 && h > 0) {
                        self.textInputRect = [x, y, w, h];
                    } else {
                        self.textInputRect = [];
                    }
                },
                wasm_open_url: (ptr, len) => {
                    let url = self.utf8decoder.decode(new Uint8Array(self.wasmResult.instance.exports.memory.buffer, ptr, len));
                    window.open(url);
                },
                wasm_download_data: (name_ptr, name_len, data_ptr, data_len) => {
                    const name = self.utf8decoder.decode(new Uint8Array(self.wasmResult.instance.exports.memory.buffer, name_ptr, name_len));
                    const data = new Uint8Array(self.wasmResult.instance.exports.memory.buffer, data_ptr, data_len);
                    const blob = new Blob([data], { type: "octet/stream" });
                    const fileURL = URL.createObjectURL(blob);
                    const dl = document.createElement('a');
                    dl.href = fileURL;
                    dl.download = name;
                    document.body.appendChild(dl);
                    dl.click();
                    document.body.removeChild(dl);
                    URL.revokeObjectURL(fileURL);
                },
                wasm_clipboardTextSet: (ptr, len) => {
                    if (len == 0) {
                        return;
                    }

                    let msg = self.utf8decoder.decode(new Uint8Array(self.wasmResult.instance.exports.memory.buffer, ptr, len));
                    if (navigator.clipboard) {
                        navigator.clipboard.writeText(msg);
                    } else {
                        self.hidden_input.value = msg;
                        self.hidden_input.focus();
                        self.hidden_input.select();
                        document.execCommand("copy");
                        self.hidden_input.value = "";
                        oskCheck();
                    }
                },
                wasm_add_noto_font: () => {
                    self.dvui_fetch("NotoSansKR-Regular.ttf").then((bytes) => {
                        //console.log("bytes len " + bytes.length);
                        const ptr = self.wasmResult.instance.exports.gpa_u8(bytes.length);
                        var dest = new Uint8Array(self.wasmResult.instance.exports.memory.buffer, ptr, bytes.length);
                        dest.set(bytes);
                        self.wasmResult.instance.exports.new_font(ptr, bytes.length);
                    });
                },
            },
        }

    }

    dvui(canvasId) {
        let self = this;

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


        //let par = document.createElement("p");
        //document.body.prepend(par);

        function oskCheck() {
            if (self.textInputRect.length == 0) {
                self.gl.canvas.focus();
            } else {
                self.hidden_input.style.left = (window.scrollX + self.gl.canvas.getBoundingClientRect().left + self.textInputRect[0]) + 'px';
                self.hidden_input.style.top = (window.scrollY + self.gl.canvas.getBoundingClientRect().top + self.textInputRect[1]) + 'px';
                self.hidden_input.style.width = self.textInputRect[2] + 'px';
                self.hidden_input.style.height = self.textInputRect[3] + 'px';
                self.hidden_input.focus();
                //par.textContent = self.hidden_input.style.left + " " + self.hidden_input.style.top + " " + self.hidden_input.style.width + " " + self.hidden_input.style.height;
            }
        }

        function touchIndex(pointerId) {
            let idx = self.touches.findIndex((e) => e[0] === pointerId);
            if (idx < 0) {
                idx = self.touches.length;
                self.touches.push([pointerId, idx]);
            }

            return idx;
        }


        // Code
        const canvas = document.querySelector(canvasId);

        self.hidden_input = document.createElement("input");
        self.hidden_input.style.position = "absolute";
        self.hidden_input.style.left = 0;
        self.hidden_input.style.top = 0;
        self.hidden_input.style.opacity = 0;
        self.hidden_input.style.zIndex = -1;
        document.body.prepend(self.hidden_input);

        self.gl = canvas.getContext("self.webgl2", { alpha: true });
        if (self.gl === null) {
            self.webgl2 = false;
            self.gl = canvas.getContext("webgl", { alpha: true });
        }

        if (self.gl === null) {
            alert("Unable to initialize WebGL.");
            return;
        }

        if (!self.webgl2) {
            const ext = self.gl.getExtension("OES_element_index_uint");
            if (ext === null) {
                alert("WebGL doesn't support OES_element_index_uint.");
                return;
            }
        }

        self.frame_buffer = self.gl.createFramebuffer();

        const vertexShader = self.gl.createShader(self.gl.VERTEX_SHADER);
        if (self.webgl2) {
            self.gl.shaderSource(vertexShader, vertexShaderSource_webgl2);
        } else {
            self.gl.shaderSource(vertexShader, vertexShaderSource_webgl);
        }
        self.gl.compileShader(vertexShader);
        if (!self.gl.getShaderParameter(vertexShader, self.gl.COMPILE_STATUS)) {
            alert(`Error compiling vertex shader: ${self.gl.getShaderInfoLog(vertexShader)}`);
            self.gl.deleteShader(vertexShader);
            return null;
        }

        const fragmentShader = self.gl.createShader(self.gl.FRAGMENT_SHADER);
        if (self.webgl2) {
            self.gl.shaderSource(fragmentShader, fragmentShaderSource_webgl2);
        } else {
            self.gl.shaderSource(fragmentShader, fragmentShaderSource_webgl);
        }
        self.gl.compileShader(fragmentShader);
        if (!self.gl.getShaderParameter(fragmentShader, self.gl.COMPILE_STATUS)) {
            alert(`Error compiling fragment shader: ${self.gl.getShaderInfoLog(fragmentShader)}`);
            self.gl.deleteShader(fragmentShader);
            return null;
        }

        self.shaderProgram = self.gl.createProgram();
        self.gl.attachShader(self.shaderProgram, vertexShader);
        self.gl.attachShader(self.shaderProgram, fragmentShader);
        self.gl.linkProgram(self.shaderProgram);

        if (!self.gl.getProgramParameter(self.shaderProgram, self.gl.LINK_STATUS)) {
            alert(`Error initializing shader program: ${self.gl.getProgramInfoLog(self.shaderProgram)}`);
            return null;
        }

        self.programInfo = {
            attribLocations: {
                vertexPosition: self.gl.getAttribLocation(self.shaderProgram, "aVertexPosition"),
                vertexColor: self.gl.getAttribLocation(self.shaderProgram, "aVertexColor"),
                textureCoord: self.gl.getAttribLocation(self.shaderProgram, "aTextureCoord"),
            },
            uniformLocations: {
                matrix: self.gl.getUniformLocation(self.shaderProgram, "uMatrix"),
                uSampler: self.gl.getUniformLocation(self.shaderProgram, "uSampler"),
                useTex: self.gl.getUniformLocation(self.shaderProgram, "useTex"),
            },
        };

        self.indexBuffer = self.gl.createBuffer();
        self.vertexBuffer = self.gl.createBuffer();

        self.gl.enable(self.gl.BLEND);
        self.gl.blendFunc(self.gl.ONE, self.gl.ONE_MINUS_SRC_ALPHA);
        self.gl.enable(self.gl.SCISSOR_TEST);
        self.gl.scissor(0, 0, self.gl.canvas.clientWidth, self.gl.canvas.clientHeight);

        let renderRequested = false;
        let renderTimeoutId = 0;
        let app_initialized = false;

        function render() {
            renderRequested = false;

            // if the canvas changed size, adjust the backing buffer
            const w = self.gl.canvas.clientWidth;
            const h = self.gl.canvas.clientHeight;
            const scale = window.devicePixelRatio;
            //console.log("wxh " + w + "x" + h + " scale " + scale);
            self.gl.canvas.width = Math.round(w * scale);
            self.gl.canvas.height = Math.round(h * scale);
            self.renderTargetSize = [self.gl.drawingBufferWidth, self.gl.drawingBufferHeight];
            self.gl.viewport(0, 0, self.gl.drawingBufferWidth, self.gl.drawingBufferHeight);
            self.gl.scissor(0, 0, self.gl.drawingBufferWidth, self.gl.drawingBufferHeight);

            self.gl.clearColor(0.0, 0.0, 0.0, 1.0); // Clear to black, fully opaque
            self.gl.clear(self.gl.COLOR_BUFFER_BIT);

            if (!app_initialized) {
                app_initialized = true;
                let app_init_return = 0;
                let str = self.utf8encoder.encode(navigator.platform);
                if (str.length > 0) {
                    const ptr = self.wasmResult.instance.exports.gpa_u8(str.length);
                    var dest = new Uint8Array(self.wasmResult.instance.exports.memory.buffer, ptr, str.length);
                    dest.set(str);
                    app_init_return = self.wasmResult.instance.exports.app_init(ptr, str.length);
                    self.wasmResult.instance.exports.gpa_free(ptr, str.length);
                } else {
                    app_init_return = self.wasmResult.instance.exports.app_init(0, 0);
                }

                if (app_init_return != 0) {
                    console.log("ERROR: app_init returned " + app_init_return);
                    return;
                }
            }

            let millis_to_wait = self.wasmResult.instance.exports.app_update();
            if (millis_to_wait == 0) {
                requestRender();
            } else if (millis_to_wait > 0) {
                renderTimeoutId = setTimeout(function () { renderTimeoutId = 0; requestRender(); }, millis_to_wait);
            }
            // otherwise something went wrong, so stop
        }

        function requestRender() {
            if (renderTimeoutId > 0) {
                // we got called before the timeout happened
                clearTimeout(renderTimeoutId);
                renderTimeoutId = 0;
            }

            if (!renderRequested) {
                // multiple events could call requestRender multiple times, and
                // we only want a single requestAnimationFrame to happen before
                // each call to app_update
                renderRequested = true;
                requestAnimationFrame(render);
            }
        }

        // event listeners
        canvas.addEventListener("contextmenu", (ev) => {
            ev.preventDefault();
        });
        window.addEventListener("resize", (ev) => {
            requestRender();
        });
        canvas.addEventListener("mousemove", (ev) => {
            let rect = canvas.getBoundingClientRect();
            let x = (ev.clientX - rect.left) / (rect.right - rect.left) * canvas.clientWidth;
            let y = (ev.clientY - rect.top) / (rect.bottom - rect.top) * canvas.clientHeight;
            self.wasmResult.instance.exports.add_event(1, 0, 0, x, y);
            requestRender();
        });
        canvas.addEventListener("mousedown", (ev) => {
            self.wasmResult.instance.exports.add_event(2, ev.button, 0, 0, 0);
            requestRender();
        });
        canvas.addEventListener("mouseup", (ev) => {
            self.wasmResult.instance.exports.add_event(3, ev.button, 0, 0, 0);
            requestRender();
            oskCheck();
        });
        canvas.addEventListener("wheel", (ev) => {
            ev.preventDefault();
            if (ev.deltaX != 0) {
                self.wasmResult.instance.exports.add_event(4, 0, 0, -ev.deltaX, 0);
            }
            if (ev.deltaY != 0) {
                self.wasmResult.instance.exports.add_event(4, 1, 0, ev.deltaY, 0);
            }
            requestRender();
        });

        let keydown = function(ev) {
            if (ev.key == "Tab") {
                // stop tab from tabbing away from the canvas
                ev.preventDefault();
            }

            let str = self.utf8encoder.encode(ev.key);
            if (str.length > 0) {
                const ptr = self.wasmResult.instance.exports.arena_u8(str.length);
                var dest = new Uint8Array(self.wasmResult.instance.exports.memory.buffer, ptr, str.length);
                dest.set(str);
                self.wasmResult.instance.exports.add_event(5, ptr, str.length, ev.repeat, (ev.metaKey << 3) + (ev.altKey << 2) + (ev.ctrlKey << 1) + (ev.shiftKey << 0));
                requestRender();
            }
        };
        canvas.addEventListener("keydown", keydown);
        self.hidden_input.addEventListener("keydown", keydown);

        let keyup = function(ev) {
            const str = self.utf8encoder.encode(ev.key);
            const ptr = self.wasmResult.instance.exports.arena_u8(str.length);
            var dest = new Uint8Array(self.wasmResult.instance.exports.memory.buffer, ptr, str.length);
            dest.set(str);
            self.wasmResult.instance.exports.add_event(6, ptr, str.length, 0, (ev.metaKey << 3) + (ev.altKey << 2) + (ev.ctrlKey << 1) + (ev.shiftKey << 0));
            requestRender();
        };
        canvas.addEventListener("keyup", keyup);
        self.hidden_input.addEventListener("keyup", keyup);

        self.hidden_input.addEventListener("beforeinput", (ev) => {
            ev.preventDefault();
            if (ev.data) {
                const str = self.utf8encoder.encode(ev.data);
                const ptr = self.wasmResult.instance.exports.arena_u8(str.length);
                var dest = new Uint8Array(self.wasmResult.instance.exports.memory.buffer, ptr, str.length);
                dest.set(str);
                self.wasmResult.instance.exports.add_event(7, ptr, str.length, 0, 0);
                requestRender();
            }
        });
        canvas.addEventListener("touchstart", (ev) => {
            ev.preventDefault();
            let rect = canvas.getBoundingClientRect();
            for (let i = 0; i < ev.changedself.touches.length; i++) {
                let touch = ev.changedself.touches[i];
                let x = (touch.clientX - rect.left) / (rect.right - rect.left);
                let y = (touch.clientY - rect.top) / (rect.bottom - rect.top);
                let tidx = touchIndex(touch.identifier);
                self.wasmResult.instance.exports.add_event(8, self.touches[tidx][1], 0, x, y);
            }
            requestRender();
        });
        canvas.addEventListener("touchend", (ev) => {
            ev.preventDefault();
            let rect = canvas.getBoundingClientRect();
            for (let i = 0; i < ev.changedself.touches.length; i++) {
                let touch = ev.changedself.touches[i];
                let x = (touch.clientX - rect.left) / (rect.right - rect.left);
                let y = (touch.clientY - rect.top) / (rect.bottom - rect.top);
                let tidx = touchIndex(touch.identifier);
                self.wasmResult.instance.exports.add_event(9, self.touches[tidx][1], 0, x, y);
                self.touches.splice(tidx, 1);
            }
            requestRender();
            oskCheck();
        });
        canvas.addEventListener("touchmove", (ev) => {
            ev.preventDefault();
            let rect = canvas.getBoundingClientRect();
            for (let i = 0; i < ev.changedself.touches.length; i++) {
                let touch = ev.changedself.touches[i];
                let x = (touch.clientX - rect.left) / (rect.right - rect.left);
                let y = (touch.clientY - rect.top) / (rect.bottom - rect.top);
                let tidx = touchIndex(touch.identifier);
                self.wasmResult.instance.exports.add_event(10, self.touches[tidx][1], 0, x, y);
            }
            requestRender();
        });
        //canvas.addEventListener("touchcancel", (ev) => {
        //    console.log(ev);
        //    requestRender();
        //});

        // start the first update
        requestRender();
    }

};
