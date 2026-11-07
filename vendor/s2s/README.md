# s2s (vendored)

Upstream: <https://github.com/ziglibs/s2s>, `master` at `2ad1e7e`.

`serialize` lay a value out as bytes for `src/hash.zig`, which hashes those
bytes with `std.hash.Wyhash`. Everything except the four items below is
upstream as-is, and `LICENCE` is upstream's MIT licence.

Upstream master targets the Zig 0.16 type-info shape and does not compile on
0.17. The port:

1. `std.lang.Type` gained `.spirv`; added to the unsupported arms of the
   serialize, deserialize, free and type-hash switches.
2. `Struct.fields`, `Enum.fields`, `Union.fields` and `ErrorSet.fields` were
   replaced by the parallel arrays `field_names`, `field_types`,
   `field_attrs`, `field_values` and `error_names`; every loop now zips those
   arrays, and `is_exhaustive` became `mode == .exhaustive`.
3. `Pointer.is_volatile` became `Pointer.attrs.@"volatile"`.
4. The comptime sorts over error and enum names need `@setEvalBranchQuota`;
   `AccessKit.Role` overflows the default 10000.

Remove this directory and go back to the `build.zig.zon` dependency once
upstream compiles on 0.17.
