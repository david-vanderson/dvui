declare namespace DVUI {
    type WasmArg =
        | string
        | WebAssembly.WebAssemblyInstantiatedSource
        | Promise<WebAssembly.WebAssemblyInstantiatedSource>
        ;

    type AllocatorFunction = (len: number) => number;
}