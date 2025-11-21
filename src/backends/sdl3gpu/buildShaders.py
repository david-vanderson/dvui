#!/usr/bin/env python3

# you shouldn't need to update any shaders for dvui's sdl3gpu, but in case you do you'll need to do a few extra steps.
# 1. get shadercross, theres a few ways to get it but it keeps changing.
# have a read of getting-shadercross.md for more info.

# this builds shaders
import os
import subprocess
import argparse

from sys import platform

origDir = os.path.abspath(os.path.dirname(__file__))

# try using shadercross from path if --sdl-shadercross isnt set
shadercross = 'shadercross'

def discoverShaders():
    rv = []
    shaderRoot = origDir
    itemlist = os.listdir(origDir)
    for x in itemlist:
        if x.endswith(".hlsl") and x != "shared.hlsl":  # Skip shared.hlsl as it's an include
            rv.append(os.path.abspath(os.path.join(shaderRoot, x)))
    return rv

def cookList(inputFiles):
    # Output to backends/sdl3gpu/compiled/
    cookedRoot = os.path.join(origDir, 'compiled')

    # we compile into 3 formats
    # dxil - DirectX Intermediate Language
    # spv  - SPIR-V (Vulkan)
    # msl  - Metal Shading Language

    outputFormats = [
        ('dxil', []),
        ('spv', []),
        ('msl', []),
    ]

    for fmt in outputFormats:
        outdir = os.path.join(cookedRoot, fmt[0])
        os.makedirs(outdir, exist_ok=True)

        for f in inputFiles:
            basefile = os.path.basename(f)[:-5]  # Remove .hlsl extension
            outfile = os.path.join(outdir, basefile + '.' + fmt[0])

            cmd = [shadercross, f] + fmt[1] + ['-o', outfile]

            print(f"Compiling {os.path.basename(f)} to {fmt[0]}...")
            print(' '.join(cmd))
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode != 0:
                print(f"Error compiling {os.path.basename(f)} to {fmt[0]}:")
                print(result.stderr)
            else:
                print(f"Successfully compiled to {outfile}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Build shaders for dvui sdl3gpu backend')
    parser.add_argument('--shadercross-path', type=str, help='Path to shadercross executable')
    args = parser.parse_args()

    if args.shadercross_path:
        shadercross = args.shadercross_path

    inputFiles = discoverShaders()
    print(inputFiles)
    cookList(inputFiles)

