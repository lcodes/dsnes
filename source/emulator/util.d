module emulator.util;

public import std.string : toStringz;

import std.conv   : to;
import std.traits : isPointer;

import derelict.lua.lua;
import derelict.opengl;
import derelict.sdl2.sdl;

alias cstring = immutable(char)*;

union ivec2 {
  struct {
    int x;
    int y;
  }
  int[2] v; alias v this;
}

void sdlRaise() {
  throw new Exception(SDL_GetError().to!string);
}

T* sdlCheck(T)(T* p) {
  if (p is null) sdlRaise();
  return p;
}

int sdlCheck(int result) {
  if (result != 0) sdlRaise();
  return result;
}

void sdlCheck(bool result) {
  if (!result) sdlRaise();
}

void _glCheck(string file = __FILE__, uint line = __LINE__)() {
  auto e = glGetError();
  if (e == GL_NO_ERROR) return;

  string msg = void;
  switch (e) {
  default: assert(0);
  case GL_OUT_OF_MEMORY:     msg = "Out of memory"; break;
  case GL_INVALID_ENUM:      msg = "Invalid enum"; break;
  case GL_INVALID_VALUE:     msg = "Invalid value"; break;
  case GL_INVALID_OPERATION: msg = "Invalid operation"; break;
  case GL_INVALID_FRAMEBUFFER_OPERATION: msg = "Invalid framebuffer operation"; break;
  }

  throw new Exception("GL: " ~ msg ~ "\n @ " ~ file ~ ":" ~ line.to!string);
}

// glCheck is `nothrow @nogc` in debug builds. This enables `debug glCheck();` in such functions.
debug {
  void glCheck(string file = __FILE__, uint line = __LINE__)() nothrow @nogc {
    alias f = _glCheck!(file, line);
    (cast(void function() nothrow @nogc) &f)();
  }
}
else {
  alias glCheck = _glCheck;
}

nothrow @nogc:

void dispose(alias destroy, T)(ref T x) if (isPointer!T) {
  if (x !is null) {
    x.destroy();
    x = null;
  }
}

void dispose(alias destroy, T)(ref T x) if (!isPointer!T) {
  if (x != 0) {
    x.destroy();
    x = 0;
  }
}

void disposeGL(alias destroy, T)(ref T x) {
  if (x != 0) {
    destroy(1, &x);
    x = 0;
  }
}

T sclamp(uint bits, T)(T x) pure {
  enum { b = 1 << (bits - 1), m = b - 1 }
  return x > m ? m : x < -b ? -b : x;
}

bool bit(uint n, T)(T x) pure {
  return cast(T)(x & (1 << n)) != 0;
}

auto bits(uint n, T)(T x) pure {
  return cast(T)(x & ((1 << (n - 1)) - 1));
}
