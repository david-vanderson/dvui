Building shadercross is quite involved, and it requires a lot of 
mixed license libraries that arent so easy to bundle together.

one of the easiest ways to get shadercross is to download it for your
platform from the github actions runners on the SDL_shadercross library:

https://github.com/libsdl-org/SDL_shadercross/actions/runs/18569748763

(thats some secret knowledge passed down directly in the SDL3 discord)

We dont use it for much in this project beyond updating the small 
shaders which should never be updated

You can use `spirv-reflect compiled/spv/<any shader here>` to  
view reflection info from the spirv version, use that to update
the fields nessecary in loadShaders() in sdl3gpu