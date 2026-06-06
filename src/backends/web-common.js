// Shared WebGL shaders
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
      vColor = aVertexColor / 255.0;
      vTextureCoord = aTextureCoord;
    }
`;

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
      vColor = aVertexColor / 255.0;
      vTextureCoord = aTextureCoord;
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
        } else {
            fragColor = vColor;
        }
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
        } else {
            gl_FragColor = vColor;
        }
    }
`;

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