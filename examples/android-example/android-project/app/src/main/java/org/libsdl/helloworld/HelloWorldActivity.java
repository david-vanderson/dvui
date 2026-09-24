package org.libsdl.helloworld;

import org.libsdl.app.SDLActivity;

public class HelloWorldActivity extends SDLActivity {
    protected String[] getLibraries() {
        return new String[] { "sdl_hello" }; // SDL3 is statically linked into it
    }
}
