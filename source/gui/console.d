/**
 * Console displaying logging messages and allowing interaction with
 * variables, commands and scripting.
 */
module gui.console;

import std.conv   : to;
import std.string : toStringz;

import std.algorithm.comparison : min;

import imgui;

import emulator.util : Singleton, cstring;
import console = emulator.console;

import layout = gui.layout;
import gui.icons;

/// Returns the most recent logging message as displayed in the GUI.
string lastLogMessage() nothrow @nogc {
  auto w = ConsoleWindow.instance;
  return w.entryStart == w.entryCount
    ? null
    : w.entryCache[w.entryStart + w.entryCount - 1];
}

/// A GUI window displaying logging messages.
class ConsoleWindow : Singleton!(ConsoleWindow, layout.Window, cstring, int),
  console.ILogger
{
  private {
    char[] filter;
    console.LogEntry[] entries;
    string[] entryCache;
    uint entryStart;
    uint entryCount;
    console.LogLevel level;
  }

  this() {
    super("Console".ptr,
          ImGuiWindowFlags_NoScrollbar |
          ImGuiWindowFlags_NoScrollWithMouse);

    filter = new char[1024];

    entries   .length = 1024;
    entryCache.length = entries.length;

    console.add(this);
  }

  ~this() {
    console.remove(this);
  }

  void updateEntryCache() {
    foreach (n; 0 .. entryCount) {
      auto id = idx(entryStart + n);
      entryCache[id] = entries[id].format(this);
    }
  }

  protected override void preDraw() {
    auto v = ImVec2(2, 2);
    ImGui.PushStyleVar(ImGuiStyleVar_WindowPadding, v);
  }

  protected override void postDraw() {
    ImGui.PopStyleVar(1);
  }

  protected override void draw() {
    drawToolbar();
    drawMessages();
    drawInput();
  }

  private void drawToolbar() {
    if (ImGui.Button(ICON_FA_BAN)) {
      entryCount = 0;
    }
    ImGui.SameLine(0, 20);

    alias label = ICON_FA_FILTER;
    ImGui.TextUnformatted(label.ptr, label.ptr + label.length);
    ImGui.SameLine();

    ImGui.InputText("##filter", filter.ptr, filter.length);
    ImGui.SameLine(0, 20);

    if (ImGui.BeginCombo("##level", "Level")) {
      bool b;
      foreach (v; __traits(allMembers, console.LogLevel)) {
        ImGui.Checkbox(v.ptr, &b);
      }
      ImGui.EndCombo();
    }

    ImGui.Separator();
  }

  private void drawMessages() {
    auto size = ImVec2(0, -ImGui.GetItemsLineHeightWithSpacing());
    ImGui.BeginChild("scrolling", size);

    auto clipper = ImGuiListClipper(entryCount, ImGui.GetTextLineHeight());

    foreach (n; clipper.DisplayStart .. clipper.DisplayEnd) {
      auto t = entryCache[idx(entryStart + n)];
      ImGui.TextUnformatted(t.ptr, t.ptr + t.length);
    }

    clipper.End();

    ImGui.EndChild();
  }

  private void drawInput() {
    ImGui.Separator();

    char[4] t = "foo";
    ImGui.InputText("##command", t.ptr, 3);
  }

  private uint idx(uint value) {
    return value % entries.length;
  }

override:
  console.LogLevel logLevel() { return level; }
  void logLevel(console.LogLevel value) { level = value; }

protected:
  void logWrite(ref const console.LogEntry e) {
    auto id = idx(entryStart + entryCount);
    entries   [id] = e;
    entryCache[id] = e.format(this);

    auto total = entries.length.to!uint;
    if (entryCount == total) {
      entryStart = idx(entryStart + 1);
    }
    else {
      entryCount = min(entryCount + 1, total);
    }
  }

  // ILogger implementation
@nogc:
  string color(console.LogLevel level) { return ""; }
  string black() { return ""; }
  string reset() { return ""; }
}
