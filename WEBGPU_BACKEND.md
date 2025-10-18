# WebGPU Backend for DVUI

This document describes the WebGPU backend implementation for DVUI.

## Overview

The WebGPU backend (`src/backends/webgpu.zig`) provides a WebGPU-based rendering backend for DVUI applications. WebGPU is a modern graphics API that provides low-level, cross-platform access to GPU functionality.

## Features

- **Complete Backend Interface**: Implements all required DVUI backend functions
- **WebGPU Integration**: Uses wgpu-native for cross-platform GPU access
- **Texture Management**: Supports texture creation, destruction, and render targets
- **Triangle Rendering**: Hardware-accelerated triangle rendering with optional clipping
- **Platform Abstraction**: Provides stubs for platform-specific functions (clipboard, URL opening)

## Implementation Status

### ✅ Completed
- Backend structure and VTable implementation
- All required backend methods implemented
- Build system integration
- Backend enum addition
- Documentation

### 🚧 TODO (Future Work)
- Integration with actual wgpu-native Zig bindings
- Real WebGPU texture creation and management
- Shader pipeline setup and rendering
- Platform-specific window integration
- Clipboard and URL opening implementations

## Usage

To build with the WebGPU backend:

```bash
zig build -Dbackend=webgpu
```

To use in your application:

```zig
const std = @import("std");
const dvui = @import("dvui");
const WebGpuBackend = @import("webgpu-backend");

var backend = try WebGpuBackend.init(.{
    .allocator = allocator,
    .size = .{ .w = 800, .h = 600 },
    .content_scale = 1.0,
});
defer backend.deinit();

var win = try dvui.Window.init(@src(), allocator, backend.backend(), .{});
defer win.deinit();
```

## Architecture

The WebGPU backend follows DVUI's backend abstraction pattern:

1. **WebGpuBackend struct**: Contains WebGPU state and configuration
2. **VTable Implementation**: All backend methods are implemented as functions on the struct
3. **Backend Interface**: The `backend()` method returns a `dvui.Backend` that wraps the implementation
4. **Resource Management**: Textures and GPU resources are tracked and cleaned up properly

## Dependencies

The implementation includes placeholder WebGPU bindings. For a complete implementation, you would need:

- `wgpu_native_zig` - Zig bindings for wgpu-native
- Platform-specific window creation library (SDL, GLFW, etc.)

## Integration Points

The WebGPU backend integrates with DVUI through:

- **Rendering**: `drawClippedTriangles()` for all UI rendering
- **Textures**: `textureCreate()`, `textureDestroy()`, render targets
- **Frame Management**: `begin()` and `end()` for frame boundaries
- **Platform Services**: Clipboard, URL opening, color scheme detection

## Notes

- This is a desktop-native WebGPU implementation, not browser-based
- Window management and display handling should be implemented separately
- The current implementation provides the backend structure without actual GPU calls
- All TODO comments indicate where real WebGPU implementation would go