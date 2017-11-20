module emulator.gui;

import std.algorithm.comparison : min;

import std.bitmanip  : bitfields;
import std.exception : assumeUnique;

import derelict.opengl;
import derelict.sdl2.sdl;

import imgui;

import emulator.util;

import console = emulator.console;
import video   = emulator.video;

import gui.icons;
import guiSystem = gui.system;

// IMGUI Interface
// -------------------------------------------------------------------------------------------------

abstract class Window {
  private Window next;

  protected {
    cstring title;
    uint    windowFlags;
    bool    open = true;
  }

  this(string title) {
    this(title.toStringz);
  }
  this(cstring title) {
    this.title = title;

    if (root is null) {
      root = this;
    }
    else {
      auto parent = root;
      while (parent.next !is null) parent = parent.next;
      parent.next = this;
    }
  }

  private void render() {
    if (ImGui.Begin(title, &open, windowFlags)) draw();
    ImGui.End();
  }

  protected void draw();
}

void tooltip(cstring desc) {
  if (ImGui.IsItemHovered()) {
    auto style = ImGui.GetStyle();
    auto alpha = style.Alpha;
    if (alpha < 1) style.Alpha = min(1, alpha * 3);

    ImGui.BeginTooltip();
    ImGui.PushTextWrapPos(450);
    ImGui.TextUnformatted(desc);
    ImGui.PopTextWrapPos();
    ImGui.EndTooltip();

    style.Alpha = alpha;
  }
}

// IMGUI Core
// -------------------------------------------------------------------------------------------------

private __gshared {
  ImGuiIO*    io;
  ImDrawData* data;

  Window root;

  double lastTime;

  GLuint program, vao, vbo, ibo, tex;
  GLuint projUniform, texUniform;

  Mouse mouse;

  bool enabled = true;

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

void initialize() {
  console.trace("Initialize");

  io = &ImGui.GetIO();

  io.KeyMap[ImGuiKey_Tab]        = SDLK_TAB;
  io.KeyMap[ImGuiKey_LeftArrow]  = SDL_SCANCODE_LEFT;
  io.KeyMap[ImGuiKey_RightArrow] = SDL_SCANCODE_RIGHT;
  io.KeyMap[ImGuiKey_UpArrow]    = SDL_SCANCODE_UP;
  io.KeyMap[ImGuiKey_DownArrow]  = SDL_SCANCODE_DOWN;
  io.KeyMap[ImGuiKey_PageUp]     = SDL_SCANCODE_PAGEUP;
  io.KeyMap[ImGuiKey_PageDown]   = SDL_SCANCODE_PAGEDOWN;
  io.KeyMap[ImGuiKey_Home]       = SDL_SCANCODE_HOME;
  io.KeyMap[ImGuiKey_End]        = SDL_SCANCODE_END;
  io.KeyMap[ImGuiKey_Delete]     = SDLK_DELETE;
  io.KeyMap[ImGuiKey_Backspace]  = SDLK_BACKSPACE;
  io.KeyMap[ImGuiKey_Enter]      = SDLK_RETURN;
  io.KeyMap[ImGuiKey_Escape]     = SDLK_ESCAPE;
  io.KeyMap[ImGuiKey_A]          = SDLK_a;
  io.KeyMap[ImGuiKey_C]          = SDLK_c;
  io.KeyMap[ImGuiKey_V]          = SDLK_v;
  io.KeyMap[ImGuiKey_X]          = SDLK_x;
  io.KeyMap[ImGuiKey_Y]          = SDLK_y;
  io.KeyMap[ImGuiKey_Z]          = SDLK_z;

  io.GetClipboardTextFn = &GetClipboardText;
  io.SetClipboardTextFn = &SetClipboardText;
  io.RenderDrawListsFn  = &RenderDrawLists;

  version (Windows) {
    SDL_SysWMinfo wmInfo = void;
    SDL_VERSION(&wmInfo.version_);
    SDL_GetWindowWMInfo(video.sdlWindow, &wmInfo).sdlCheck;
    io.ImeWindowHandle = wmInfo.info.win.window;
  }

  program = glCreateProgram();
  auto vert = glCreateShader(GL_VERTEX_SHADER);
  auto frag = glCreateShader(GL_FRAGMENT_SHADER);
  glShaderSource(vert, 1, &vertexShader,   null);
  glShaderSource(frag, 1, &fragmentShader, null);
  glCompileShader(vert);
  glCompileShader(frag);
  checkShader(vert);
  checkShader(frag);
  glAttachShader(program, vert);
  glAttachShader(program, frag);
  glLinkProgram(program);
  checkProgram(program);
  glDeleteShader(vert);
  glDeleteShader(frag);
  debug glCheck();

  texUniform  = glGetUniformLocation(program, "tex");
  projUniform = glGetUniformLocation(program, "proj");
  auto pos = glGetAttribLocation(program, "in_pos");
  auto uv  = glGetAttribLocation(program, "in_uv");
  auto col = glGetAttribLocation(program, "in_col");
  debug glCheck();

  glGenVertexArrays(1, &vao);
  glBindVertexArray(vao);
  glGenBuffers(1, &vbo);
  glGenBuffers(1, &ibo);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glEnableVertexAttribArray(pos);
  glEnableVertexAttribArray(uv);
  glEnableVertexAttribArray(col);
  glVertexAttribPointer(pos, 2, GL_FLOAT,         GL_FALSE, ImDrawVert.sizeof, cast(void*) ImDrawVert.pos.offsetof);
  glVertexAttribPointer(uv,  2, GL_FLOAT,         GL_FALSE, ImDrawVert.sizeof, cast(void*) ImDrawVert.uv .offsetof);
  glVertexAttribPointer(col, 4, GL_UNSIGNED_BYTE, GL_TRUE,  ImDrawVert.sizeof, cast(void*) ImDrawVert.col.offsetof);
  glBindVertexArray(0);
  debug glCheck();

  io.Fonts.AddFontDefault();

  ImFontConfig fc;
  fc.MergeMode= true;
  ImWchar[3] iconRanges = [ICON_MIN_FA, ICON_MAX_FA, 0];
  io.Fonts.AddFontFromFileTTF("fonts/fontawesome-webfont.ttf", 13, &fc, iconRanges.ptr);

  ubyte* pixels = void;
  int width = void, height = void;
  io.Fonts.GetTexDataAsAlpha8(&pixels, &width, &height, null);

  glGenTextures(1, &tex);
  glBindTexture(GL_TEXTURE_2D, tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, width, height, 0, GL_RED, GL_UNSIGNED_BYTE, pixels);
  debug glCheck();

  io.Fonts.SetTexID(cast(void*) tex);
  io.Fonts.ClearInputData();
  io.Fonts.ClearTexData();
}

void checkInfoLog(alias pname, alias get, alias getInfo)(GLuint name) {
  GLint status;
  get(name, pname, &status);

  if (status == GL_FALSE) {
    GLint length;
    get(name, GL_INFO_LOG_LENGTH, &length);

    auto err = new char[length];
    getInfo(name, length, &length, err.ptr);

    throw new Exception(err.assumeUnique);
  }
}

alias checkShader  = checkInfoLog!(GL_COMPILE_STATUS, glGetShaderiv,  glGetShaderInfoLog);
alias checkProgram = checkInfoLog!(GL_LINK_STATUS,    glGetProgramiv, glGetProgramInfoLog);

void terminate() {
  console.trace("Terminate");

  tex.disposeGL!glDeleteTextures;
  ibo.disposeGL!glDeleteBuffers;
  vbo.disposeGL!glDeleteBuffers;
  vao.disposeGL!glDeleteVertexArrays;

  program.dispose!glDeleteProgram;

  ImGui.Shutdown();
}

bool processEvent(SDL_Event* event) {
  if (!enabled) return false;

  switch (event.type) {
  default: return false;

  case SDL_MOUSEWHEEL:
    /**/ if (event.wheel.y > 0) mouse.wheel =  1;
    else if (event.wheel.y < 0) mouse.wheel = -1;
    return true;

  case SDL_MOUSEBUTTONDOWN:
    switch (event.button.button) {
    default: return false;
    case SDL_BUTTON_LEFT:   mouse.left   = true; return true;
    case SDL_BUTTON_RIGHT:  mouse.right  = true; return true;
    case SDL_BUTTON_MIDDLE: mouse.middle = true; return true;
    }

  case SDL_TEXTINPUT:
    io.AddInputCharactersUTF8(event.text.text.ptr);
    return true;

  case SDL_KEYDOWN:
  case SDL_KEYUP:
    auto key = event.key.keysym.sym & ~SDLK_SCANCODE_MASK;
    auto mod = SDL_GetModState();
    io.KeysDown[key] = event.type == SDL_KEYDOWN;
    io.KeyShift = (mod & KMOD_SHIFT) != 0;
    io.KeyAlt   = (mod & KMOD_CTRL)  != 0;
    io.KeySuper = (mod & KMOD_GUI)   != 0;
    return true;
  }
}

void run() {
  if (!enabled) return;

  int ww = void, wh = void;
  int dw = void, dh = void;
  SDL_GetWindowSize(video.sdlWindow, &ww, &wh);
  SDL_GL_GetDrawableSize(video.sdlWindow, &dw, &dh);
  io.DisplaySize = ImVec2(ww, wh);
  io.DisplayFramebufferScale = ImVec2(ww > 0 ? cast(float) dw / ww : 0,
                                      wh > 0 ? cast(float) dh / dh : 0);

  auto time    = SDL_GetTicks() / cast(double) 1000;
  io.DeltaTime = lastTime > 0 ? time - lastTime : 1f / 60;
  lastTime     = time;

  int mx = void, my = void;
  auto mouseMask = SDL_GetMouseState(&mx, &my);
  if (SDL_GetWindowFlags(video.sdlWindow) & SDL_WINDOW_MOUSE_FOCUS) {
    io.MousePos = ImVec2(mx, my);
  }
  else {
    io.MousePos = ImVec2(-float.max, -float.max);
  }

  io.MouseDown[0] = mouse.left   || (mouseMask & SDL_BUTTON(SDL_BUTTON_LEFT))   != 0;
  io.MouseDown[1] = mouse.right  || (mouseMask & SDL_BUTTON(SDL_BUTTON_RIGHT))  != 0;
  io.MouseDown[2] = mouse.middle || (mouseMask & SDL_BUTTON(SDL_BUTTON_MIDDLE)) != 0;
  // io.MouseWheel = mouse.wheel * 0.25;

  mouse.buttons = 0;
  mouse.wheel   = 0;

  SDL_ShowCursor(!io.MouseDrawCursor);

  ImGui.NewFrame();
  guiSystem.draw();

  // __gshared bool open;
  // ImGui.ShowTestWindow(&open);

  auto window = root;
  while (window !is null) {
    window.render();
    window = window.next;
  }

  ImGui.Render();
}

// IMGUI Shader
// -------------------------------------------------------------------------------------------------

immutable vertexShader = q{
  #version 330

  in vec2 in_pos;
  in vec2 in_uv;
  in vec4 in_col;

  out vec2 uv;
  out vec4 col;

  uniform mat4 proj;

  void main() {
    gl_Position = proj * vec4(in_pos, 0, 1);

    col = in_col;
    uv  = in_uv;
  }
}.ptr;

immutable fragmentShader = q{
  #version 330

  in vec2 uv;
  in vec4 col;

  out vec4 fragColor;

  uniform sampler2D tex;

  void main() {
    fragColor = col * texture(tex, uv).r;
  }
}.ptr;

// IMGUI Callbacks
// -------------------------------------------------------------------------------------------------

extern (C++) nothrow:

const(char)* GetClipboardText(void* user_data) {
  return SDL_GetClipboardText();
}

void SetClipboardText(void* user_data, const(char)* text) {
  SDL_SetClipboardText(text);
}

void RenderDrawLists(ImDrawData* drawData) {
  data = drawData;
  auto width = cast(GLsizei) io.DisplaySize.x;
  auto height = cast(GLsizei) io.DisplaySize.y;
  // auto width  = cast(GLsizei) (io.DisplaySize.x * io.DisplayFramebufferScale.x);
  // auto heImGui.ht = cast(GLsizei) (io.DisplaySize.y * io.DisplayFramebufferScale.y);
  // if (width == 0 || heImGui.ht == 0) return;

  // drawData.ImDataDraw_ScaleClipRects(io.DisplayFramebufferScale);

  glEnable(GL_BLEND);
  glBlendEquation(GL_FUNC_ADD);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDisable(GL_CULL_FACE);
  glDisable(GL_DEPTH_TEST);
  glEnable(GL_SCISSOR_TEST);
  glActiveTexture(GL_TEXTURE0);
  glViewport(0, 0, width, height);

  scope auto orthographic = [2f / io.DisplaySize.x, 0,                       0, 0,
                              0,                    2f / -io.DisplaySize.y,  0, 0,
                              0,                    0,                      -1, 0,
                             -1,                    1,                       0, 1];

  glUseProgram(program);
  glUniform1i(texUniform, 0);
  glUniformMatrix4fv(projUniform, 1, GL_FALSE, orthographic.ptr);
  glBindVertexArray(vao);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);

  foreach (n; 0 .. drawData.CmdListsCount) {
    auto cmdList = drawData.CmdLists[n];

    glBufferData(GL_ARRAY_BUFFER,
                 cmdList.VtxBuffer.Size * ImDrawVert.sizeof,
                 cmdList.VtxBuffer.Data, GL_STREAM_DRAW);

    glBufferData(GL_ELEMENT_ARRAY_BUFFER,
                 cmdList.IdxBuffer.Size * ImDrawIdx.sizeof,
                 cmdList.IdxBuffer.Data, GL_STREAM_DRAW);

    ImDrawIdx* idxOffset;
    auto cmd = cmdList.CmdBuffer.Data;
    auto end = cmdList.CmdBuffer.Size + cmd;
    for (; cmd != end; cmd++) {
      if (cmd.UserCallback) {
        cmd.UserCallback(cmdList, cmd);
      }
      else {
        glBindTexture(GL_TEXTURE_2D, cast(GLuint) cmd.TextureId);
        glScissor(cast(GLsizei) (cmd.ClipRect.x),
                  cast(GLsizei) (height - cmd.ClipRect.w),
                  cast(GLsizei) (cmd.ClipRect.z - cmd.ClipRect.x),
                  cast(GLsizei) (cmd.ClipRect.w - cmd.ClipRect.y));

        enum indexType = ImDrawIdx.sizeof == 2 ? GL_UNSIGNED_SHORT : GL_UNSIGNED_INT;
        glDrawElements(GL_TRIANGLES, cmd.ElemCount, indexType, idxOffset);
      }

      idxOffset += cmd.ElemCount;
    }
  }

  glDisable(GL_SCISSOR_TEST);
  debug glCheck();
}
