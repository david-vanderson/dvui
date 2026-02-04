export type WasmArg =
    | string
    | WebAssembly.WebAssemblyInstantiatedSource
    | Promise<WebAssembly.WebAssemblyInstantiatedSource>
;

interface DvuiOptions {
    wasmImportsExtra: WebAssembly.Imports | undefined
}

/** instantiates a Dvui object, sets the WASM, and starts rendering */
export function dvui(
    canvas: string | HTMLCanvasElement,
    wasmRef: WasmArg
): Promise<Dvui>;

/**
 * if you need more control over the initialization, you can instantiate a Dvui instance yourself
 * and start it later
 */
export interface Dvui {
    setInstance(inst: WebAssembly.Instance): void;
    /** can be an element or a string selector to query for an element */
    setCanvas(canvas: string | HTMLCanvasElement): void;
    //render(): void;
    stop(): void;
    run(): void;
    restart(): void;
    requestRender(): void;
    init(): void;
    imports: WebAssembly.ModuleImports;
}

export const Dvui: new() => Dvui;
