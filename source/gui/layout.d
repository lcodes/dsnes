/**
 * Manages GUI _windows and their disposition within the native window.
 */
module gui.layout;

import std.conv      : to;
import std.exception : enforce;

import imgui;

import emulator.profiler : Profile;
import emulator.util : cstring;
import console = emulator.console;

private __gshared {
  Window[] _windows; /// Array of created windows.
  Window active;     /// Window at the top of the single mode chain.
  Window nextActive; /// Window to make active at the end of frame.

  void function() _draw; /// Currently active window layout function.
}

package __gshared {
  bool showMenu    = true;  /// Whether to show the main menu bar.
  bool showStatus  = true;  /// Whether to show the main status bar.
  bool showTest    = false; /// Whether to show the ImGui test window.
  bool showMetrics = false; /// Whether to show the ImGui metrics window.

  float menuBarHeight;   /// Set from gui.menu.
  float statusBarHeight; /// Set from gui.status.
}

nothrow @nogc {
  void ImGui_BeginDisabled() {
    ImGui.PushItemFlag(ImGuiItemFlags_Disabled, true);
    ImGui.PushStyleVar(ImGuiStyleVar_Alpha, ImGui.GetStyle().Alpha * 0.5f);
  }

  void ImGui_EndDisabled() {
    ImGui.PopStyleVar();
    ImGui.PopItemFlag();
  }

  version(none) // Buggy
  bool ImGui_Splitter(bool vertical, float thickness,
                      float* size1, float* size2,
                      float minSize1 = 100, float minSize2 = 100,
                      float splitterLength = -1)
  {
    auto g = GImGui;
    auto w = g.CurrentWindow;
    auto id = w.GetID("##Splitter");

    ImRect bb = void;
    bb.Min = w.DC.CursorPos + (vertical ? ImVec2(*size1, 0.0f) : ImVec2(0.0f, *size2));
    bb.Max = bb.Min + ImGui.CalcItemSize(vertical
                                         ? ImVec2(thickness, splitterLength)
                                         : ImVec2(splitterLength, thickness),
                                         0.0f, 0.0f);

    auto axis = vertical ? ImGuiAxis.X : ImGuiAxis.Y;
    return ImGui.SplitterBehavior(id, bb, axis, size1, size2,
                                  minSize1, minSize2, 0.0f);
  }

  /// Returns the current display size minus menu and status bar areas.
  ImVec2 displaySizeAdjusted() {
    auto size = ImGui.GetIO().DisplaySize;
    size.y -= menuBarHeight + statusBarHeight;
    return size;
  }

  /// Returns an array of all windows.
  Window[] windows() { return _windows; }

  /// Returns the first window of type ci.
  Window window(ClassInfo ci) {
    foreach (w; _windows) {
      if (w.classinfo is ci) {
        return w;
      }
    }
    return null;
  }
  /// Returns the first window of type T.
  Window windowT(T : Window)() {
    auto w = typeid(T).window;
    assert(w);
    return w;
  }
}

/// A GUI window drawn on screen using ImGui.
abstract class Window {
  /// Constructs a new Window given its initial window.
  this(cstring title, uint flags = 0) {
    assert(title);
    console.trace("New window: ", title);

    this._title = title;
    this.flags = flags;

    if (active is null) {
      active = this;
    }

    foreach (ubyte idx, ref slot; _windows) {
      if (slot is null) {
        slot = this;
        id   = idx;
        return;
      }
    }

    enforce(_windows.length < ubyte.max, "Too many _windows");
    id = _windows.length.to!ubyte;

    _windows ~= this;
  }

  nothrow @nogc {
    /// Sets this window as active. This makes it visible in single mode.
    void setActive() {
      next = active;
      nextActive = this;
      activate = true;
    }

    /// Gives back active status to the window last having it.
    void restoreActive() {
      nextActive = next;
      next = null;
    }
  }

  bool open = true; /// Whether the window is displayed on screen.

  const nothrow @nogc {
    /// Read-only window title.
    cstring title() { return _title; }

    /// When true, show an entry in the window menu to toggle visibility.
    bool showInWindowMenu() { return true; }

    /// Number used to sort entries in the window menu.
    double menuIndex() { return 0; }

    /// Show inside a sub-menu of the window menu. Use / for multiple levels.
    string subMenuPath() { return ""; }
  }

protected:
  cstring _title;   /// Window title to pass to ImGui.Begin() each frame.
  uint    flags;    /// Window flags to pass to ImGui.Begin() each frame.
  ubyte   id;       /// Unique window identifier. Also the position in windows.
  bool    activate; /// Whether the window wants focus on the next frame.

  /// Called between ImGui.Begin() and ImGui.End().
  abstract void draw();

  /// Called before ImGui.Begin().
  void preDraw() {}

  /// Called after ImGui.End();
  void postDraw() {}

  nothrow @nogc {
    /// When true, the previously active window is also drawn in single mode.
    bool canDrawNext() { return true; }
  }

private:
  Window next; /// The window that was active before this one.
}

bool isSingle() nothrow @nogc {
  return _draw is &drawSingle;
}
void setSingle(bool enable) {
  _draw = enable ? &drawSingle : &drawMulti;
}

package:

void initialize(ClassInfo[] windowTypes) {
  ImGui.StyleColorsDark();
  ImGui.GetStyle().ScrollbarSize = 10;

  _draw = &drawSingle;
  _windows.length = windowTypes.length;

  foreach (type; windowTypes) {
    auto obj = type.create();
    enforce(obj !is null, "Failed to create window");
    enforce(cast(Window) obj !is null, "Not a window");
  }
}

void terminate() {
  foreach (w; _windows) {
    delete w;
  }

  _windows.length = 0;
}

void draw() {
  scope auto p = new Profile!();

  assert(_draw);
  _draw();

  if (nextActive) {
    active = nextActive;
    nextActive = null;
  }
}

/// Combination of window flags removing most ImGui features.
enum fixedWindowFlags =
  ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize    |
  ImGuiWindowFlags_NoMove     | ImGuiWindowFlags_NoScrollbar |
  ImGuiWindowFlags_NoSavedSettings;

immutable pivotCenter = ImVec2(0.5, 0.5);

/// Positions the next GUI window at the center of the native window.
void ImGui_SetNextWindowPosCenter(ImGuiCond cond = 0) {
  auto io  = &ImGui.GetIO();
  auto pos = ImVec2(io.DisplaySize.x * 0.5,
                    io.DisplaySize.y * 0.5f);

  ImGui.SetNextWindowPos(pos, cond, pivotCenter);
}

private:

/// Draws one window in single mode layout.
void drawSingle1(Window window, ref const ImVec2 pos, ref const ImVec2 size,
                 int depth = 0)
{
  assert(depth < 10, "Single mode layout active window overflow");

  // FIXME: seems to work to make active window on top. Not sure if consistent.
  if (window.next && window.canDrawNext) {
    window.next.drawSingle1(pos, size, depth + 1);
  }

  window.preDraw(); // Before pushing window vars; want to override settings.

  if (window.activate) {
    window.activate = false;
    ImGui.SetNextWindowFocus();
  }

  char[10] title = "##layoutN"; // Using window.title would store new settings.
  title[9] = cast(char) ('0' + depth);

  ImGui.SetNextWindowPos(pos);
  ImGui.SetNextWindowSize(size);
  ImGui.PushStyleVar(ImGuiStyleVar_WindowRounding, 0);
  ImGui.Begin(title.ptr, null, fixedWindowFlags | window.flags);

  window.draw();

  ImGui.End();
  ImGui.PopStyleVar(1);

  window.postDraw();
}

/// Draws the active window chain using the full display size.
void drawSingle() {
  if (active is null) return;

  auto pos  = ImVec2(0, menuBarHeight);
  auto size = displaySizeAdjusted;

  active.drawSingle1(pos, size);
}

/// Draws all open windows with user-defined positions and sizes.
void drawMulti() {
  foreach (window; _windows) {
    if (window.open) {
      window.preDraw();

      if (ImGui.Begin(window._title, &window.open, window.flags)) {
        window.draw();
      }
      ImGui.End();

      window.postDraw();
    }
  }
}
