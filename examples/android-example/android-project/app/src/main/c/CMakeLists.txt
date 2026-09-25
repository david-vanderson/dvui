cmake_minimum_required(VERSION 3.12.0)
project(sdl_hello)

# Built by `zig build lib` in ../zig-project (single ABI: arm64-v8a).
set(ZIG_OUT_LIB ${CMAKE_SOURCE_DIR}/../../../../../zig-project/zig-out/lib)

add_library(sdl_hello_lib STATIC IMPORTED)
set_target_properties(sdl_hello_lib PROPERTIES IMPORTED_LOCATION ${ZIG_OUT_LIB}/libsdl_hello.a)
add_library(sdl3_lib STATIC IMPORTED)
set_target_properties(sdl3_lib PROPERTIES IMPORTED_LOCATION ${ZIG_OUT_LIB}/libSDL3.a)

add_library(sdl_hello SHARED main.c)
target_include_directories(sdl_hello PRIVATE ${ZIG_OUT_LIB}/../include)
# whole-archive: SDL's JNI entry points (JNI_OnLoad, Java_org_libsdl_app_*) are only
# looked up at runtime by the JVM, so a plain static link would drop them.
target_link_libraries(sdl_hello PRIVATE
    sdl_hello_lib
    -Wl,--whole-archive sdl3_lib -Wl,--no-whole-archive
    android log dl m EGL GLESv1_CM GLESv2 OpenSLES)
