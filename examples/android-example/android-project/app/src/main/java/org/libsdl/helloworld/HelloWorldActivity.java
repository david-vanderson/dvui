package org.libsdl.helloworld;

import org.libsdl.app.SDLActivity;

public class HelloWorldActivity extends SDLActivity {
    protected String[] getLibraries() {
        return new String[] { "SDL3", "sdl_hello" };
    }
}
