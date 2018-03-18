/**
 * Utilities used throughout the application.
 *
 * This module is the answer to "where should I put this?" and should not
 * import any first-party modules.
 */
module emulator.util;

import std.conv      : parse, text;
import std.exception : assumeUnique, enforce;
import std.traits    : isPointer;

import derelict.lua.lua;
import derelict.opengl;

debug enum debugging = true;
else  enum debugging = false;

mixin template noCtors() {
  @disable this();
  @disable this(this);
}

template featureEnabled(string name,
                        bool debugDefault = true,
                        bool ddocDefault = true)
{
  debug enum featureEnabled = debugDefault;
  else version (ddoc) enum featureEnabled = ddocDefault;
  else mixin("version (" ~ name ~ ") enum featureEnabled = true;" ~
             "else enum featureEnabled = false;");
}

// Types
// -----------------------------------------------------------------------------

/// Immutable C string.
alias cstring = immutable(char)*;

/// 8-bit register
alias Reg8 = ubyte;

/// 16-bit register
union Reg16 {
  ushort w; alias w this;
  struct { ubyte l, h; }

  ref ubyte opIndex(bool i) nothrow @nogc {
    return i ? h : l;
  }

  private unittest {
    assert(Reg16(0xff00).h == 0xff);
  }
}

/// 24-bit register
union Reg24 {
  uint d; alias d this;
  struct { ushort w, wh; }
  struct { ubyte l, h, b, bh; }

  private unittest {
    assert(Reg24(0xff_dead).b == 0xff);
    assert(Reg24(0xff_face).w == 0xface);
  }
}

static assert(Reg8 .sizeof == 1);
static assert(Reg16.sizeof == 2);
static assert(Reg24.sizeof == 4);

/// Helper to compare semantic version numbers.
union Version {
  uint number; /// The number holding all version components.

  struct {
    version (ddoc) {
      ubyte major; ///
      ubyte minor; ///
      ubyte patch; ///
    }
    else version (LittleEndian) {
      ubyte patch;
      ubyte minor;
      ubyte major;
      private ubyte _unused;
    }
    else {
      private ubyte _unused;
      ubyte major;
      ubyte minor;
      ubyte patch;
    }
  }

  /// Constructs a version number from components.
  this(ubyte major, ubyte minor = 0, ubyte patch = 0) {
    this.major = major;
    this.minor = minor;
    this.patch = patch;
  }

  /// Parses a version string in the 'major.minor.patch' format.
  static Version parse(string str) {
    Version v;

    v.major = str.parse!ubyte();
    enforce(str[0] == '.', "Invalid version number: " ~ str);

    str = str[1..$];
    v.minor = str.parse!ubyte();

    if (str.length && str[0] == '.') {
      v.patch = str.parse!ubyte();
    }
    else {
      v.patch = 0;
    }

    return v;
  }

const:
  /// Creates a string representation of the version number.
  string toString() {
    if (patch == 0) return text(major, '.', minor);
    return text(major, '.', minor, '.', patch);
  }

nothrow @nogc:
  /// Returns true if rhs has the same version number.
  bool opEquals(Version rhs) {
    return number == rhs.number;
  }

  /// Compares with another version number.
  int opCmp(Version rhs) {
    if (number == rhs.number) {
      return 0;
    }

    return number < rhs.number ? -1 : 1;
  }
}

unittest {
  assert(Version(1)      .number == 0x00010000);
  assert(Version(1, 2)   .number == 0x00010200);
  assert(Version(1, 2, 3).number == 0x00010203);

  assert(Version(1)       < Version(2));
  assert(Version(1, 2)    < Version(1, 3));
  assert(Version(1, 2, 3) > Version(1, 2, 0));

  assert(Version(4, 2, 0) == Version(4, 2, 0));
}

/// Singleton class.
abstract class Singleton(Derived, Base = Object, CtorArgs...) : Base {
  private static __gshared Derived _instance;

  static Derived instance() nothrow @nogc {
    assert(_instance !is null, "Missing singleton instance");
    return _instance;
  }

  this(CtorArgs args) {
    assert(_instance is null);

    super(args);

    _instance = cast(Derived) this;
    assert(_instance !is null);
  }

  ~this() {
    assert(_instance !is null);
    _instance = null;
  }
}

/// 2D integer vector
union ivec2 {
  struct {
    int x; ///
    int y; ///
  }
  int[2] v; ///
  alias v this;
}

/// OpenGL helpers
// -----------------------------------------------------------------------------

GLuint compileShader(GLuint stage, string src) {
  return compileShader(stage, (&src)[0..1]);
}
/// ditto
GLuint compileShader(GLuint stage, in string[] srcs) {
  import core.stdc.stdlib : alloca;
  auto p = cast(cstring*) alloca(srcs.length * cstring.sizeof);
  auto l = cast(int*)     alloca(srcs.length * int.sizeof);

  foreach (i, s; srcs) {
    p[i] = s.ptr;
    l[i] = cast(uint) s.length;
  }

  auto shader = glCreateShader(stage);
  scope (failure) glDeleteShader(shader);

  glShaderSource(shader, cast(uint) srcs.length, p, l);
  glCompileShader(shader);
  checkShader(shader);

  return shader;
}

GLuint linkProgram(GLuint vert, GLuint frag) {
  auto prog = glCreateProgram();
  scope (failure) glDeleteProgram(prog);

  glAttachShader(prog, vert);
  glAttachShader(prog, frag);
  glLinkProgram(prog);
  checkProgram(prog);

  return prog;
}

void _glCheck(string file = __FILE__, uint line = __LINE__)() {
  auto e = glGetError();
  if (e == GL_NO_ERROR) return;

  string msg;
  switch (e) {
  default: assert(0, "Unknown GL error");
  case GL_OUT_OF_MEMORY:     msg = "Out of memory";     break;
  case GL_INVALID_ENUM:      msg = "Invalid enum";      break;
  case GL_INVALID_VALUE:     msg = "Invalid value";     break;
  case GL_INVALID_OPERATION: msg = "Invalid operation"; break;
  case GL_INVALID_FRAMEBUFFER_OPERATION:
    msg = "Invalid framebuffer operation";
    break;
  }

  throw new Exception(text("GL: ", msg, "\n @ ", file, ":", line));
}

// glCheck is `nothrow @nogc` in debug builds. This enables `debug glCheck();` in such functions.
debug {
  /// Throws an exception if there is an error on the active GL context.
  void glCheck(string file = __FILE__, uint line = __LINE__)() nothrow @nogc {
    alias f = _glCheck!(file, line);
    (cast(void function() nothrow @nogc) &f)();
  }
}
else {
  alias glCheck = _glCheck;
}

void checkInfoLog(alias pname, alias get, alias getInfo)(GLuint name) {
  GLint status;
  get(name, pname, &status);
  debug glCheck();

  if (status == GL_FALSE) {
    GLint length;
    get(name, GL_INFO_LOG_LENGTH, &length);

    auto err = new char[length];
    getInfo(name, length, &length, err.ptr);

    debug glCheck();
    throw new Exception(err.assumeUnique);
  }
}

alias checkShader  = checkInfoLog!(GL_COMPILE_STATUS,
                                   glGetShaderiv,
                                   glGetShaderInfoLog);
alias checkProgram = checkInfoLog!(GL_LINK_STATUS,
                                   glGetProgramiv,
                                   glGetProgramInfoLog);

// Low-level functions
// -----------------------------------------------------------------------------

nothrow @nogc:

/// Safely destroys an object and sets its reference to null.
void dispose(alias destroy, T)(ref T x) if (isPointer!T) {
  if (x !is null) {
    x.destroy();
    x = null;
  }
}
/// ditto
void dispose(alias destroy, T)(ref T x) if (!isPointer!T) {
  if (x != 0) {
    x.destroy();
    x = 0;
  }
}
/// Safely destroys an OpenGL object and sets its reference to zero.
void disposeGL(alias destroy, T)(ref T x) {
  if (x != 0) {
    destroy(1, &x);
    x = 0;
  }
}

/// Signed bit clamp.
T sclamp(uint bits, T)(T x) pure {
  enum { b = 1 << (bits - 1), m = b - 1 }
  return x > m ? m : x < -b ? -b : x;
}

/// Test whether a bit is set.
bool bit(uint n, T)(T x) pure {
  return cast(T)(x & (1 << n)) != 0;
}

/// Strip to a number of bits.
auto bits(uint n, T)(T x) pure {
  return cast(T)(x & ((1 << (n - 1)) - 1));
}
