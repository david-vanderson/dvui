cmake_minimum_required(VERSION 3.12.0)
project(sdl_hello)

find_package(SDL3 CONFIG REQUIRED)

add_library(sdl_hello_lib STATIC IMPORTED)
set_target_properties(sdl_hello_lib PROPERTIES IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/prebuilt/${ANDROID_ABI}/libsdl_hello.a)

add_library(sdl_hello SHARED main.c)
target_link_libraries(sdl_hello PRIVATE sdl_hello_lib SDL3::SDL3)
