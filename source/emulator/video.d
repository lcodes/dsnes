/**
 * Handles the display window and the OpenGL state to draw its contents.
 *
 * OpenGL 2.1 is a minimum requirement. Modern features and extensions will be
 * used as required and available. The GLState context wrapper is used to
 * hide away these low-level details away from other modules.
 * TODO: vulkan support? other display backends?
 *
 * User events related to the window's frame are handled by this module, while
 * input events are delegated to the emulator.input module.
 *
 * References:
 *   http://graphics.stanford.edu/courses/cs148-10-summer/docs/FreeImage3131.pdf
 */
module emulator.video;

import std.algorithm.comparison : min;
import std.bitmanip  : bitfields;
import std.conv      : to;
import std.exception : enforce;
import std.string    : toStringz;

import derelict.freeimage.freeimage;
import derelict.glfw3;
import derelict.opengl;

import emulator.profiler : Profile;
import emulator.util : Version, cstring, debugging, dispose, glCheck, ivec2;
import console = emulator.console;

static assert(GLFW_DONT_CARE == -1);

// Video State
// -----------------------------------------------------------------------------

enum Api : ubyte {
  OpenGL,
  Vulkan
}

private __gshared {
  GLFWwindow* _window;

  Settings settings;
  Capabilities caps;
  Extensions exts;

  struct Settings {
    ivec2 pos  = ivec2(  -1,  -1);
    ivec2 size = ivec2(1600, 960);

    Version glVersion = Version(3, 3); // TODO: 2.1
    short refreshRate = GLFW_DONT_CARE;
    Api api = Api.OpenGL;
    bool vsyncEnabled = true;
    bool resizable = true;
    bool decorated = true;
    bool floating = false;
    bool maximized = false;
    bool srgb = true;
    bool doubleBuffered = true;
  }
}

// OpenGL Capabilities and Extensions
// -----------------------------------------------------------------------------

struct Capabilities {
  enum Vendor {
    nVidia,
    ATI,
    Intel,
    unknown
  }

  Version glVersion;
  Version glslVersion;
  Vendor  vendor;

private:

  void initializeVersion() {
    // OpenGL version and vendor
    auto ver = glGetString(GL_VERSION).to!string;
    auto ven = glGetString(GL_VENDOR) .to!string;
    auto renderer = glGetString(GL_RENDERER);
    auto glsl = glGetString(GL_SHADING_LANGUAGE_VERSION).to!string;
    glCheck(); // Make sure these strings are valid.

    glVersion   = Version.parse(ver);
    glslVersion = Version.parse(glsl);

    switch (ven) {
    case "Intel Inc.": vendor = Vendor.Intel; break;
    default:           vendor = Vendor.unknown;
    }

    console.verbose("OpenGL version ", glVersion, " (", ver, ")");
    console.verbose("OpenGL vendor: ", vendor,    " (", ven, ")");
    console.verbose("OpenGL renderer: ", renderer);
    console.verbose("GLSL version " , glslVersion, " (", glsl, ")");
    enforce(glVersion >= Version(2, 1), "OpenGL 2.1 is required.");
  }

  void initialize() {
    // TODO
    debug glCheck();
  }
}

struct Extensions {
  // Common
  // TODO: anisotropic
  // TODO: s3tc (+ srgb)
  // TODO: debug (+ output)

  // GL 3.3
  // TODO: get program binary
  // TODO: explicit uniform location
  // TODO: vertex attrib binding

  // GL 2.1
  // TODO: vao
  // TODO: fbo
  // TODO: map buffer range
  // TODO: texture rectangle
  // TODO: bindable uniforms
  // TODO: framebuffer_sRGB

  private static bool glExtensionSupported(in char* name) {
    auto result = glfwExtensionSupported(name) == GLFW_TRUE;
    if (result) {
      console.verbose("Using OpenGL extension: ", name);
    }
    return result;
  }

  private void initialize() {
    // Common
    if (glExtensionSupported("GL_EXT_texture_filter_anisotropic")) {

    }

    if (glExtensionSupported("GL_EXT_texture_compression_s3tc")) {
      if (glExtensionSupported("GL_EXT_texture_sRGB")) {

      }
    }

    if (glExtensionSupported("GL_ARB_debug_output")) {

    }

    if (glExtensionSupported("GL_KHR_debug")) {

    }

    // GL 3.3
    if (glExtensionSupported("GL_ARB_get_program_binary")) {

    }

    if (glExtensionSupported("GL_ARB_explicit_uniform_location")) {

    }

    if (glExtensionSupported("GL_ARB_vertex_attrib_binding")) {

    }

    // GL 2.1
    if (glExtensionSupported("GL_ARB_vertex_array_object")) {

    }

    if (glExtensionSupported("GL_ARB_framebuffer_object")) {

    }

    if (glExtensionSupported("GL_ARB_map_buffer_range")) {

    }

    if (glExtensionSupported("GL_ARB_texture_rectangle")) {

    }

    if (glExtensionSupported("GL_EXT_bindable_uniform")) {

    }

    if (glExtensionSupported("GL_EXT_framebuffer_sRGB")) {

    }

    debug glCheck();
  }
}

// OpenGL State
// -----------------------------------------------------------------------------

__gshared GLState gl; /// OpenGL state management.

/**
 * Tracking of OpenGL state to reduce driver calls overhead. Prefer these
 * methods over directly calling OpenGL. Failing to do so may result in state
 * desynchronization.
 *
 * Also hides away the OpenGL version and extensions in used in order to provide
 * a single consistent interface to other modules.
 */
struct GLState {
nothrow @nogc:

  void viewport(GLint x, GLint y, GLsizei width, GLsizei height) {
    if (_viewport.x != x || _viewport.width  != width ||
        _viewport.y != y || _viewport.height != height)
    {
      _viewport = Viewport(x, y, width, height);
      glViewport(0, 0, width, height);
    }
  }

  void program(uint prog) {
    if (_program != prog) {
      _program = prog;
      glUseProgram(prog);
    }
  }

  void vertexArray(uint vao) {
    if (_vertexArray != vao) {
      _vertexArray = vao;
      glBindVertexArray(vao);
    }
  }

  void vertexBuffer(uint vbo) {
    if (_vertexBuffer != vbo) {
      _vertexBuffer = vbo;
      glBindBuffer(GL_ARRAY_BUFFER, vbo);
    }
  }

  void indexBuffer(uint ibo) {
    if (_indexBuffer != ibo) {
      _indexBuffer = ibo;
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
    }
  }

  void uniformBuffer(uint ubo) {
    if (_uniformBuffer != ubo) {
      _uniformBuffer = ubo;
      glBindBuffer(GL_UNIFORM_BUFFER, ubo);
    }
  }

  void activeTexture(uint unit)
  in {
    assert(unit < _textures.length);
  }
  body {
    if (_texUnit != unit) {
      _texUnit = cast(ubyte) unit;
      glActiveTexture(GL_TEXTURE0 + unit);
    }
  }

  void texture2D(uint tex) {
    if (_textures[_texUnit] != tex) {
      _textures[_texUnit] = tex;
      glBindTexture(GL_TEXTURE_2D, tex);
    }
  }

  void scissor(GLsizei x, GLsizei y, GLsizei width, GLsizei height) {
    if (_scissor.x != x || _scissor.width  != width ||
        _scissor.y != y || _scissor.height != height)
    {
      _scissor = Scissor(x, y, width, height);
      glScissor(x, y, width, height);
    }
  }

  void blendEnable() {
    if (!_blend) {
      _blend = true;
      glEnable(GL_BLEND);
    }
  }
  void blendDisable() {
    if (_blend) {
      _blend = false;
      glDisable(GL_BLEND);
    }
  }

  void scissorTestEnable() {
    if (!_scissorTest) {
      _scissorTest = true;
      glEnable(GL_SCISSOR_TEST);
    }
  }
  void scissorTestDisable() {
    if (_scissorTest) {
      _scissorTest = false;
      glDisable(GL_SCISSOR_TEST);
    }
  }

private:
  static struct Scissor {
    GLsizei x, y, width, height;
  }

  static struct Viewport {
    GLint x, y;
    GLsizei width, height;
  }

  GLuint[8] _textures;
  Scissor   _scissor;
  Viewport  _viewport;
  GLuint    _program;
  GLuint    _vertexArray;
  GLuint    _vertexBuffer;
  GLuint    _indexBuffer;
  GLuint    _uniformBuffer;
  ubyte     _texUnit;

  mixin(bitfields!(bool, "_blend",       1,
                   bool, "_scissorTest", 1,
                   byte, "_unused",      6));
}

// Image Loading
// -----------------------------------------------------------------------------

FREE_IMAGE_FORMAT imageFormat(cstring path) {
  auto format = path.FreeImage_GetFileType(0);
  if (format == FIF_UNKNOWN) {
    format = path.FreeImage_GetFIFFromFilename();
  }

  enforce(format.FreeImage_FIFSupportsReading(), "Cannot read image.");
  return format;
}

FIBITMAP* openImage(string path) {
  auto src = path.toStringz;
  auto bmp = FreeImage_Load(src.imageFormat, src);

  assert(bmp !is null);
  return bmp;
}

alias closeImage = FreeImage_Unload;

void transformImage(alias op, Args...)(ref FIBITMAP* bmp, Args args) {
  auto tmp = op(bmp, args);
  assert(tmp !is null);

  bmp.FreeImage_Unload();
  bmp = tmp;
}

/// Loads an image into an existing texture, resizing it to fit as needed.
void loadImage(FIBITMAP* bmp, GLuint texture,
               uint x, uint y, ref uint w, ref uint h)
{
  scope (exit) bmp.FreeImage_Unload();

  auto bpp = bmp.FreeImage_GetBPP();
  if (bpp != 32) {
    bmp.transformImage!FreeImage_ConvertTo32Bits();
  }

  auto width  = bmp.FreeImage_GetWidth();
  auto height = bmp.FreeImage_GetHeight();

  if (w != width || h != height) {
    auto scale = min(cast(double) w / width, cast(double) h / height);
    w = cast(uint) (scale * width);
    h = cast(uint) (scale * height);

    bmp.transformImage!FreeImage_Rescale(w, h, FILTER_BILINEAR);
  }

  gl.texture2D = texture;
  glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h, GL_BGRA, GL_UNSIGNED_BYTE,
                  bmp.FreeImage_GetBits());
  glCheck();
}

/// Loads an image into an existing texture at a fixed position and size.
void loadImage(string path, GLuint tex, uint x, uint y, ref uint w, ref uint h) {
  path.openImage().loadImage(tex, x, y, w, h);
}

/// Loads an image into a new texture and returns it.
GLuint loadImage(string path) {
  auto bmp = path.openImage();

  GLuint tex;
  glGenTextures(1, &tex);
  scope (failure) glDeleteTextures(1, &tex);

  auto w = bmp.FreeImage_GetWidth();
  auto h = bmp.FreeImage_GetHeight();
  bmp.loadImage(tex, 0, 0, w, h);

  return tex;
}

// Native Window Reference
// -----------------------------------------------------------------------------

mixin DerelictGLFW3_NativeBind!();

nothrow @nogc {
  GLFWwindow* window() { return _window; }
  void* nativeWindow() { return _window ? _nativeWindow : null; }

private:
  version (linux) {
    // TODO: Mir and Wayland?
    private void* _nativeWindow() { return _window.glfwGetX11Window(); }
  }
  else version (OSX) {
    alias void* id;
    alias uint  CGDirectDisplayID;

    __gshared {
      da_glfwGetCocoaMonitor glfwGetCocoaMonitor;
      da_glfwGetCocoaWindow  glfwGetCocoaWindow;
      da_glfwGetNSGLContext  glfwGetNSGLContext;
    }

    private void* _nativeWindow() { return _window.glfwGetCocoaWindow(); }
  }
  else version (Windows) {
    private void* _nativeWindow() { return _window.glfwGetWin32Window(); }
  }
  else {
    private void* _nativeWindow() { return null; }
  }
}

// Lifecycle
// -----------------------------------------------------------------------------

package:

void initialize() {
  console.trace("Initialize");

  DerelictFI.load();

  // Load GLFW functions used to support the nativeWindow function.
  DerelictGLFW3_loadNative();

  // Window related hints
  glfwWindowHint(GLFW_RESIZABLE,    settings.resizable);
  glfwWindowHint(GLFW_VISIBLE,      true);
  glfwWindowHint(GLFW_DECORATED,    settings.decorated);
  glfwWindowHint(GLFW_AUTO_ICONIFY, false);
  glfwWindowHint(GLFW_FLOATING,     settings.floating);
  glfwWindowHint(GLFW_MAXIMIZED,    settings.maximized);

  // Framebuffer related hints
  glfwWindowHint(GLFW_RED_BITS,     8); // Output RGB8 images.
  glfwWindowHint(GLFW_GREEN_BITS,   8);
  glfwWindowHint(GLFW_BLUE_BITS,    8);
  glfwWindowHint(GLFW_ALPHA_BITS,   0);
  glfwWindowHint(GLFW_DEPTH_BITS,   0); // Don't need depth/stencil.
  glfwWindowHint(GLFW_STENCIL_BITS, 0);
  glfwWindowHint(GLFW_SAMPLES,      0);
  glfwWindowHint(GLFW_SRGB_CAPABLE, settings.srgb);
  glfwWindowHint(GLFW_DOUBLEBUFFER, settings.doubleBuffered);

  // Monitor related hints
  glfwWindowHint(GLFW_REFRESH_RATE, settings.refreshRate);

  // Context related hints
  if (settings.api != Api.OpenGL) {
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API); // Don't init OpenGL.
  }
  else {
    auto forwardCompat = settings.glVersion >= Version(3, 2);

    glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_API); // TODO: support ES?
    // glfwWindowHint(GLFW_CONTEXT_CREATION_API, GLFW_NATIVE_CONTEXT_API);

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, settings.glVersion.major);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, settings.glVersion.minor);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, forwardCompat);
    glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT,  debugging); // Ignored on macOS.

    if (forwardCompat) {
      glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    }

    glfwWindowHint(GLFW_CONTEXT_ROBUSTNESS,       GLFW_LOSE_CONTEXT_ON_RESET);
    glfwWindowHint(GLFW_CONTEXT_RELEASE_BEHAVIOR, GLFW_RELEASE_BEHAVIOR_NONE);
    // glfwWindowHint(GLFW_CONTEXT_NO_ERROR, !debugging);
  }

  // Create the window
  // TODO: fullscreen
  // TODO: title
  GLFWmonitor* monitor = null; // TODO: get monitor for fullscreen
  _window = glfwCreateWindow(settings.size.x, settings.size.y, "DEMU",
                             monitor, null);
  enforce(_window, "Failed to create a window");

  with (settings.pos)
  if (x != -1 && y != -1) {
    _window.glfwSetWindowPos(x, y);
  }

  // FIXME: configurable? or set from current system?
  _window.glfwSetWindowSizeLimits(320, 200, GLFW_DONT_CARE, GLFW_DONT_CARE);
  _window.glfwSetWindowAspectRatio(4, 3);

  _window.glfwSetWindowPosCallback(&onPos);
  _window.glfwSetWindowSizeCallback(&onSize);
  _window.glfwSetWindowCloseCallback(&onClose);
  _window.glfwSetWindowRefreshCallback(&onRefresh);
  _window.glfwSetWindowFocusCallback(&onFocus);
  _window.glfwSetWindowIconifyCallback(&onIconify);
  _window.glfwSetFramebufferSizeCallback(&onFramebufferSize);

  console.add("video.pos",    &settings.pos.x,  &move);
  console.add("video.size",   &settings.pos.y,  &move);
  console.add("video.width",  &settings.size.x, &resize);
  console.add("video.height", &settings.size.y, &resize);

  // Initialize the OpenGL context
  _window.glfwMakeContextCurrent();

  glfwSwapInterval(settings.vsyncEnabled);

  DerelictGL3.load();
  DerelictGL3.reload();

  caps.initializeVersion();
  exts.initialize();
  caps.initialize();

  // OpenGL state set once and never touched again
  glDisable(GL_CULL_FACE);
  glBlendEquation(GL_FUNC_ADD);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glCheck();
}

void terminate() {
  console.trace("Terminate");

  if (DerelictGL3.isLoaded) {
    DerelictGL3.unload();

    quit();
  }
}

void run() nothrow @nogc {
  scope auto p = new Profile!();

  // TODO: blit video out, no clear; GUI goes on top anyways
  gl.scissorTestDisable();
  glClearColor(.4, .3, .2, 1);
  glClear(GL_COLOR_BUFFER_BIT);
  debug glCheck();
}

void end() nothrow @nogc {
  scope auto p = new Profile!();

  glCheck();
  _window.glfwSwapBuffers();
}

void quit() {
  if (DerelictGLFW3.isLoaded) {
    glfwMakeContextCurrent(null);

    _window.dispose!glfwDestroyWindow();
  }
}

// Emulator Interface
// -----------------------------------------------------------------------------

// These functions are called by emulator systems.

nothrow:

/// Called when an emulator system is ready to present a new frame.
public void refresh(void* output, uint pitch, uint width, uint height) @nogc {
  // TODO:
}

// Native Window Commands
// -----------------------------------------------------------------------------

// These functions are called when configuration changes to update the
// corresponding window state.

private:

void move() {
  assert(_window !is null);
  with (settings.pos) _window.glfwSetWindowPos(x, y);
}

void resize() {
  assert(_window !is null);
  with (settings.size) _window.glfwSetWindowSize(x, y);
}

// Native Window Event Handlers
// -----------------------------------------------------------------------------

// These functions are called by GLFW in response to user window events. They
// are mostly used to keep configuration synchronized with the window state.

extern(C):

void onPos(GLFWwindow* window, int x, int y) {
  settings.pos.x = x;
  settings.pos.y = y;
}

void onSize(GLFWwindow* window, int width, int height) {
  settings.size.x = width;
  settings.size.y = height;
}

void onClose(GLFWwindow* window) {
  console.error("TODO CLOSE");
  // TODO?
}

void onRefresh(GLFWwindow* window) {
  console.error("TODO REFRESH ");
  // TODO?
}

void onFocus(GLFWwindow* window, int focused) {
  // TODO?
}

void onIconify(GLFWwindow* window, int iconified) {
  // TODO?
}

void onFramebufferSize(GLFWwindow* window, int width, int height) {
  // TODO?
  console.error("TODO FBO ", width, "x", height);
}
