/**
 * Integration of Dear IMGUI. Contains low-level GUI functions.
 * See the gui.system module for high-level GUI functions.
 *
 * Invokes the high-level drawing code and handles submitting render commands to
 * the GPU.
 *
 * References:
 * - https://github.com/ocornut/imgui
 * - https://github.com/ocornut/imgui/blob/master/imgui.h
 * - https://github.com/ocornut/imgui/tree/master/examples/opengl3_example
 */
module emulator.gui;

import std.algorithm : min;
import std.bitmanip  : bitfields;
import std.exception : enforce;
import std.file      : exists;
import std.path      : buildPath;
import std.string    : toStringz;

import derelict.opengl;
import derelict.glfw3.glfw3;

import imgui;

import emulator.profiler : Profile;
import emulator.util;
import console = emulator.console;
import user    = emulator.user;
import video   = emulator.video;

import gui.icons : ICON_MIN_FA, ICON_MAX_FA;
import gui.fonts : Font, fonts;
import guiSystem = gui.system;

debug = GuiTest;

// Core
// -----------------------------------------------------------------------------

private __gshared {
  string iniFilename; /// GC reference
  double lastTime;    /// Used to measure delta time
  ImGuiIO* io;        /// ImGui handle
  GLuint alphaProgram, colorProgram; /// OpenGL GUI programs
  GLuint vao, vbo, ibo, ubo, tex; /// OpenGL objects
  Mouse mouse; /// Mouse state collected from input events
  bool _enabled = true; // Whether to render gui or not

  ubyte [Font.max + 1] fontSizes = [13, 16, 28, 14];
  string[Font.max + 1] fontNames = [null,
                                    "Futura.ttc",
                                    "Tahoma Bold.ttf",
                                    "SourceCodePro-Regular.ttf"];

  struct Mouse {
    byte wheel;
    union {
      ubyte buttons;
      mixin(bitfields!(bool, "left",   1,
                       bool, "right",  1,
                       bool, "middle", 1,
                       byte, "unused", 5));
    }
  }
}

nothrow @nogc {
  bool enabled() { return _enabled; }
  void enabled(bool value) {
    if (_enabled != value) {
      _enabled = value;

      if (value) {
        lastTime = -1;
        resetInput();
      }
    }
  }
}

// Utilities
// -----------------------------------------------------------------------------

nothrow @nogc {
  void filesLayout() { guiSystem.filesWindow.setActive(); }
  void gameLayout () { guiSystem.gameWindow .setActive(); }

  /// Display a tooltip if the last ImGui element is hovered.
  void tooltip(string desc, uint textWrapPos = 450) {
    if (ImGui.IsItemHovered()) {
      auto style = ImGui.GetStyle();
      auto alpha = style.Alpha;

      if (alpha < 1) {
        style.Alpha = min(1, alpha * 3);
      }

      ImGui.BeginTooltip();
      ImGui.PushTextWrapPos(textWrapPos);
      ImGui.TextUnformatted(desc.ptr, desc.ptr + desc.length);
      ImGui.PopTextWrapPos();
      ImGui.EndTooltip();

      style.Alpha = alpha;
    }
  }
}

// Lifecycle
// -----------------------------------------------------------------------------

package:

private uint setupProgram(uint prog) nothrow @nogc {
  video.gl.program = prog;

  glUniform1i(glGetUniformLocation(prog, "tex"), 0);
  glUniformBlockBinding(prog, glGetUniformBlockIndex(prog, "GUI"), 0);
  debug glCheck();

  return prog;
}

void initialize() {
  console.trace("Initialize");

  io = &ImGui.GetIO();

  iniFilename = user.dataPath ~ "/imgui.ini\0";
  io.IniFilename = iniFilename.ptr;

  io.KeyMap[ImGuiKey_Tab]        = GLFW_KEY_TAB;
  io.KeyMap[ImGuiKey_LeftArrow]  = GLFW_KEY_LEFT;
  io.KeyMap[ImGuiKey_RightArrow] = GLFW_KEY_RIGHT;
  io.KeyMap[ImGuiKey_UpArrow]    = GLFW_KEY_UP;
  io.KeyMap[ImGuiKey_DownArrow]  = GLFW_KEY_DOWN;
  io.KeyMap[ImGuiKey_PageUp]     = GLFW_KEY_PAGEUP;
  io.KeyMap[ImGuiKey_PageDown]   = GLFW_KEY_PAGEDOWN;
  io.KeyMap[ImGuiKey_Home]       = GLFW_KEY_HOME;
  io.KeyMap[ImGuiKey_End]        = GLFW_KEY_END;
  io.KeyMap[ImGuiKey_Delete]     = GLFW_KEY_DELETE;
  io.KeyMap[ImGuiKey_Backspace]  = GLFW_KEY_BACKSPACE;
  io.KeyMap[ImGuiKey_Enter]      = GLFW_KEY_ENTER;
  io.KeyMap[ImGuiKey_Escape]     = GLFW_KEY_ESCAPE;
  io.KeyMap[ImGuiKey_A]          = GLFW_KEY_A;
  io.KeyMap[ImGuiKey_C]          = GLFW_KEY_C;
  io.KeyMap[ImGuiKey_V]          = GLFW_KEY_V;
  io.KeyMap[ImGuiKey_X]          = GLFW_KEY_X;
  io.KeyMap[ImGuiKey_Y]          = GLFW_KEY_Y;
  io.KeyMap[ImGuiKey_Z]          = GLFW_KEY_Z;

  io.GetClipboardTextFn = &getClipboardText;
  io.SetClipboardTextFn = &setClipboardText;
  io.RenderDrawListsFn  = &renderDrawLists;

  version (Windows) {
    io.ImeWindowHandle = video.nativeWindow;
  }

  auto vert = compileShader(GL_VERTEX_SHADER, vertexShader);
  scope (exit) glDeleteShader(vert);

  auto alphaSource = [fragmentShaderProlog, fragmentShaderAlpha];
  auto alphaShader = compileShader(GL_FRAGMENT_SHADER, alphaSource);
  scope (exit) glDeleteShader(alphaShader);

  auto colorSource = [fragmentShaderProlog, fragmentShaderColor];
  auto colorShader = compileShader(GL_FRAGMENT_SHADER, colorSource);
  scope (exit) glDeleteShader(colorShader);

  alphaProgram = linkProgram(vert, alphaShader).setupProgram();
  colorProgram = linkProgram(vert, colorShader).setupProgram();

  glGenVertexArrays(1, &vao);
  video.gl.vertexArray = vao;

  glBindVertexArray(vao);
  glGenBuffers(1, &vbo);
  glGenBuffers(1, &ibo);
  video.gl.vertexBuffer = vbo;

  glEnableVertexAttribArray(0);
  glEnableVertexAttribArray(1);
  glEnableVertexAttribArray(2);

  enum size = ImDrawVert.sizeof;
  auto posOffset = cast(void*) ImDrawVert.pos.offsetof;
  auto uvOffset  = cast(void*) ImDrawVert.uv .offsetof;
  auto colOffset = cast(void*) ImDrawVert.col.offsetof;
  glVertexAttribPointer(0, 2, GL_FLOAT,         GL_FALSE, size, posOffset);
  glVertexAttribPointer(1, 2, GL_FLOAT,         GL_FALSE, size, uvOffset);
  glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, GL_TRUE,  size, colOffset);

  video.gl.vertexArray = 0;
  debug glCheck();

  glGenBuffers(1, &ubo);
  video.gl.uniformBuffer = ubo;

  ImFontConfig fc;
  ImFont* f;

  auto fontPaths = user.fontPaths;
  foreach (uint idx, name; fontNames) {
    fc.SizePixels = fontSizes[idx];

    if (name.length == 0) {
      assert(idx == 0);
      f = io.Fonts.AddFontDefault(&fc);
    }
    else {
      bool found;
      foreach (p; fontPaths) {
        auto tryPath = p.buildPath(name);
        if (tryPath.exists()) {
          f = io.Fonts.AddFontFromFileTTF(tryPath.toStringz(),
                                          fc.SizePixels, &fc);
          found = true;
          break;
        }
      }

      enforce(found, "Font not found: " ~ name);
    }

    // if (idx == Font.normal || idx == Font.heading) {
      fc.MergeMode = true;

      ImWchar[3] iconRanges = [ICON_MIN_FA, ICON_MAX_FA, 0];
      io.Fonts.AddFontFromFileTTF("fonts/fontawesome-webfont.ttf",
                                  fc.SizePixels, &fc, iconRanges.ptr);

      // TODO: load Symbola ?

      fc.MergeMode = false;
    // }

    fonts[idx] = f;
  }

  ubyte* pixels = void;
  int width = void, height = void;
  io.Fonts.GetTexDataAsAlpha8(&pixels, &width, &height, null);
  console.verbose("Font texture size: ", width, "x", height);

  glGenTextures(1, &tex);
  video.gl.texture2D = tex;
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, width, height, 0, GL_RED, GL_UNSIGNED_BYTE, pixels);
  debug glCheck();

  io.Fonts.SetTexID(cast(void*) tex);
  io.Fonts.ClearInputData();
  io.Fonts.ClearTexData();

  guiSystem.initialize();
}

void terminate() {
  console.trace("Terminate");

  guiSystem.terminate();

  tex.disposeGL!glDeleteTextures;
  ubo.disposeGL!glDeleteBuffers;
  ibo.disposeGL!glDeleteBuffers;
  vbo.disposeGL!glDeleteBuffers;
  vao.disposeGL!glDeleteVertexArrays;

  alphaProgram.dispose!glDeleteProgram;
  colorProgram.dispose!glDeleteProgram;

  ImGui.Shutdown();
}

private void setup() nothrow @nogc {
  int ww = void, wh = void;
  int dw = void, dh = void;
  video.window.glfwGetWindowSize(&ww, &wh);
  video.window.glfwGetFramebufferSize(&dw, &dh);
  io.DisplaySize = ImVec2(ww, wh);
  io.DisplayFramebufferScale = ImVec2(ww > 0 ? cast(float) dw / ww : 0,
                                      wh > 0 ? cast(float) dh / wh : 0);

  auto time    = glfwGetTime();
  io.DeltaTime = lastTime > 0 ? time - lastTime : 1f / 60;
  lastTime     = time;

  if (!video.window.glfwGetWindowAttrib(GLFW_FOCUSED)) {
    io.MousePos = ImVec2(-float.max, -float.max);
  }
  else if (io.WantMoveMouse) {
    video.window.glfwSetCursorPos(io.MousePos.x, io.MousePos.y);
  }
  else {
    double mx = void, my = void;
    video.window.glfwGetCursorPos(&mx, &my);
    io.MousePos = ImVec2(mx, my);
  }

  io.MouseDown[0] = mouse.left   || video.window.glfwGetMouseButton(0);
  io.MouseDown[1] = mouse.right  || video.window.glfwGetMouseButton(1);
  io.MouseDown[2] = mouse.middle || video.window.glfwGetMouseButton(2);
  io.MouseWheel   = mouse.wheel * 0.25;
  resetInput();

  auto cursorMode = io.MouseDrawCursor ? GLFW_CURSOR_HIDDEN : GLFW_CURSOR_NORMAL;
  video.window.glfwSetInputMode(GLFW_CURSOR, cursorMode);
}

void run() {
  if (!enabled) return;

  scope auto p = new Profile!();

  setup();

  {
    scope auto p1 = new Profile!();
    ImGui.NewFrame();
  }

  guiSystem.draw();

  {
    scope auto p1 = new Profile!();
    ImGui.Render();
  }
}

// IMGUI Shaders
// -----------------------------------------------------------------------------

// This is a very simple shader used for all GUI draw calls. Except maybe
// for custom draw logic implemented in some components.
//
// The vertex stage applies an orthographic projection to a 2D position while
// the fragment stage combines the vertex color with a texture sample.
//
// The output is in RGBA and expects alpha blending after the pixel stage.
//
// TODO: sRGB?

immutable vertexShader = q{
  #version 410

  layout(location=0) in vec2 in_pos;
  layout(location=1) in vec2 in_uv;
  layout(location=2) in vec4 in_col;

  out vec2 uv;
  out vec4 col;

  layout (std140) uniform GUI {
    mat4 proj;
  } gui;

  void main() {
    gl_Position = gui.proj * vec4(in_pos, 0, 1);

    col = in_col;
    uv  = in_uv;
  }
};

immutable fragmentShaderProlog = q{
  #version 330

  in vec2 uv;
  in vec4 col;

  layout(location=0) out vec4 fragColor;

  uniform sampler2D tex;
};

immutable fragmentShaderAlpha = q{
  void main() {
    // float color = texture(tex, uv).r;
    // float width = fwidth(color);
    // float alpha = smoothstep(0.5 - width, 0.5 + width, color);
    // fragColor = vec4(col.rgb * color, col.a * alpha);
    fragColor = col * texture(tex, uv).r;
  }
};

immutable fragmentShaderColor = q{
  void main() {
    fragColor = col * texture(tex, uv);
  }
};

// Input Handlers
// -----------------------------------------------------------------------------

// These functions are called from the emulator.input module in response to
// user input events. They are used to communicate these events to IMGUI.

nothrow @nogc:

void resetInput() {
  mouse.buttons = 0;
  mouse.wheel   = 0;
}

void onKey(int key, int action) {
  io.KeysDown[key] = action == GLFW_PRESS;
  io.KeyAlt   = io.KeysDown[GLFW_KEY_LEFT_ALT] ||
                io.KeysDown[GLFW_KEY_RIGHT_ALT];
  io.KeyCtrl = io.KeysDown[GLFW_KEY_LEFT_CONTROL] ||
               io.KeysDown[GLFW_KEY_RIGHT_CONTROL];
  io.KeyShift = io.KeysDown[GLFW_KEY_LEFT_SHIFT] ||
                io.KeysDown[GLFW_KEY_RIGHT_SHIFT];
  io.KeySuper = io.KeysDown[GLFW_KEY_LEFT_SUPER] ||
                io.KeysDown[GLFW_KEY_RIGHT_SUPER];
}

void onChar(uint codepoint) {
  if (codepoint < 0x10000) {
    io.AddInputCharacter(cast(ushort) codepoint);
  }
}

void onMouseButton(int button, int action) {
  auto press = action == GLFW_PRESS;
  switch (button) {
  case GLFW_MOUSE_BUTTON_LEFT:   mouse.left   = press; break;
  case GLFW_MOUSE_BUTTON_RIGHT:  mouse.right  = press; break;
  case GLFW_MOUSE_BUTTON_MIDDLE: mouse.middle = press; break;
  default:
  }
}

void onScroll(double offset) {
  /**/ if (offset > 0) mouse.wheel += 1;
  else if (offset < 0) mouse.wheel -= 1;
}

// IMGUI Callbacks
// -----------------------------------------------------------------------------

// These functions are called by IMGUI in response to certain events.

extern (C++):

/// Called when the user wants to paste text into an input box.
const(char)* getClipboardText(void* userData) {
  return video.window.glfwGetClipboardString();
}

/// Called when the user wants to copy or cut text from an input box.
void setClipboardText(void* userData, const(char)* text) {
  video.window.glfwSetClipboardString(text);
}

/// IMGUI can be built with either 16- or 32-bit indices.
enum indexType = ImDrawIdx.sizeof == 2 ? GL_UNSIGNED_SHORT : GL_UNSIGNED_INT;

/// Called from within ImGui.Render() to submit its draw lists to the GPU.
void renderDrawLists(ImDrawData* drawData) {
  auto width  = cast(GLsizei) (io.DisplaySize.x * io.DisplayFramebufferScale.x);
  auto height = cast(GLsizei) (io.DisplaySize.y * io.DisplayFramebufferScale.y);
  if (width == 0 || height == 0) return;

  drawData.ScaleClipRects(io.DisplayFramebufferScale);

  video.gl.blendEnable();
  video.gl.scissorTestEnable();
  video.gl.viewport(0, 0, width, height);

  float[16] orthographic =
    [2f / io.DisplaySize.x, 0,                       0, 0,
      0,                    2f / -io.DisplaySize.y,  0, 0,
      0,                    0,                      -1, 0,
     -1,                    1,                       0, 1];


  video.gl.vertexArray   = vao;
  video.gl.vertexBuffer  = vbo;
  video.gl.indexBuffer   = ibo;
  video.gl.uniformBuffer = ubo;

  enum mat4Size = orthographic.length * float.sizeof;
  glBufferData(GL_UNIFORM_BUFFER, mat4Size, orthographic.ptr, GL_DYNAMIC_DRAW);
  glBindBufferRange(GL_UNIFORM_BUFFER, 0, ubo, 0, mat4Size);

  foreach (n; 0 .. drawData.CmdListsCount) {
    auto cmdList = drawData.CmdLists[n];

    glBufferData(GL_ARRAY_BUFFER,
                 cmdList.VtxBuffer.Size * ImDrawVert.sizeof,
                 cmdList.VtxBuffer.Data,
                 GL_STREAM_DRAW);

    glBufferData(GL_ELEMENT_ARRAY_BUFFER,
                 cmdList.IdxBuffer.Size * ImDrawIdx.sizeof,
                 cmdList.IdxBuffer.Data,
                 GL_STREAM_DRAW);

    ImDrawIdx* idxOffset;
    auto cmd = cmdList.CmdBuffer.Data;
    auto end = cmdList.CmdBuffer.Size + cmd;
    for (; cmd != end; cmd++) {
      if (cmd.UserCallback) {
        cmd.UserCallback(cmdList, cmd);
      }
      else {
        auto texture = cast(uint) cmd.TextureId;
        video.gl.texture2D = texture;

        video.gl.program = texture == tex ? alphaProgram : colorProgram;

        video.gl.scissor(cast(GLsizei) (cmd.ClipRect.x),
                         cast(GLsizei) (height - cmd.ClipRect.w),
                         cast(GLsizei) (cmd.ClipRect.z - cmd.ClipRect.x),
                         cast(GLsizei) (cmd.ClipRect.w - cmd.ClipRect.y));

        glDrawElements(GL_TRIANGLES, cmd.ElemCount, indexType, idxOffset);
      }

      idxOffset += cmd.ElemCount;
    }
  }

  debug glCheck();
}
