export type WasmArg =
    | string
    | WebAssembly.WebAssemblyInstantiatedSource
    | Promise<WebAssembly.WebAssemblyInstantiatedSource>
;

interface DvuiOptions {
    wasmImportsExtra: WebAssembly.Imports | undefined
}

export function dvui(
    canvas: string | HTMLCanvasElement,
    wasmRef: WasmArg
): Dvui;

export interface Dvui {}
