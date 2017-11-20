module emulator.video;

import derelict.opengl;
import derelict.sdl2.sdl;

import emulator.util : ivec2, glCheck, sdlCheck, dispose;

import console = emulator.console;

private __gshared {
  SDL_Window*   window;
  SDL_GLContext context;

  Settings settings;

  struct Settings {
    ivec2 pos  = ivec2(SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED);
    ivec2 size = ivec2(1600, 960);
  }
}

nothrow @nogc {
  SDL_Window*   sdlWindow()  { return window; }
  SDL_GLContext sdlContext() { return context; }
}

package:

void initialize() {
  console.trace("Initialize");
  console.add("video.pos",    &settings.pos.x,  &move);
  console.add("video.size",   &settings.pos.y,  &move);
  console.add("video.width",  &settings.size.x, &resize);
  console.add("video.height", &settings.size.y, &resize);

  int contextFlags;
  contextFlags |= SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG; // TODO: osx only?
  debug contextFlags |= SDL_GL_CONTEXT_DEBUG_FLAG;

  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
  SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE,   0);
  SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 0);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS,        contextFlags);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);

  // SDL_DisplayMode current = void;
  // SDL_GetCurrentDisplayMode(0, &current);

  auto windowFlags = SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE;
  window  = SDL_CreateWindow("DEMU", settings.pos.x, settings.pos.y,
                             settings.size.x, settings.size.y, windowFlags).sdlCheck;
  context = SDL_GL_CreateContext(window).sdlCheck;

  SDL_GL_MakeCurrent(window, context).sdlCheck;

  DerelictGL3.load();
  DerelictGL3.reload();

  console.verbose("OpenGL ",  glGetString(GL_VERSION));
  console.verbose("Renderer", glGetString(GL_RENDERER));
  console.verbose("Vendor",   glGetString(GL_VENDOR));
  glCheck();

  // TODO: show extensions
}

void terminate() {
  console.trace("Terminate");

  if (DerelictGL3.isLoaded) {
    DerelictGL3.unload();
  }

  if (DerelictSDL2.isLoaded) {
    SDL_GL_MakeCurrent(null, null).sdlCheck;

    context.dispose!SDL_GL_DeleteContext();
    window .dispose!SDL_DestroyWindow();
  }
}

void run() {
  glClearColor(.4, .3, .2, 1);
  glClear(GL_COLOR_BUFFER_BIT);
  debug glCheck();
}

void end() {
  glCheck();
  SDL_GL_SwapWindow(window);
}

private void move() {
  assert(window !is null);
  window.SDL_SetWindowPosition(settings.pos.x, settings.pos.y);
}

private void resize() {
  assert(window !is null);
  window.SDL_SetWindowSize(settings.size.x, settings.size.y);
}

nothrow @nogc:

void onMove(int x, int y) {
  settings.pos.x = x;
  settings.pos.y = y;
}

void onResize(int width, int height) {
  settings.size.x = width;
  settings.size.y = height;
}

public void refresh(void* output, uint pitch, uint width, uint height) {

}
