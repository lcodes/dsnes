module gui.console;

import std.conv : to;

import std.algorithm.comparison : min;

import imgui;

import emulator.util : cstring, toStringz;

import console = emulator.console;
import gui     = emulator.gui;

class ConsoleWindow : gui.Window, console.ILogger {
  private {
    console.LogEntry[] entries;
    cstring[] entryCache;
    uint entryStart;
    uint entryCount;
    console.LogLevel level;
  }

  this() {
    super("Console".ptr);

    entries.length = 1024;
    entryCache.length = entries.length;

    console.add(this);
  }

  void updateEntryCache() {
    foreach (n; 0 .. entryCount) {
      auto id = idx(entryStart + n);
      entryCache[id] = entries[id].format(this).toStringz();
    }
  }

  protected override void draw() {
    if (ImGui.Button("Clear")) {
      console.info("NOPE");
    }

    auto size = ImVec2(0, -ImGui.GetItemsLineHeightWithSpacing());
    ImGui.Separator();
    ImGui.BeginChild("##scrolling", size);
    auto clipper = ImGuiListClipper(entryCount, ImGui.GetTextLineHeight());

    foreach (n; clipper.DisplayStart .. clipper.DisplayEnd) {
      ImGui.Text(entryCache[idx(entryStart + n)]);
    }

    clipper.End();
    ImGui.EndChild();
  }

  protected override void logWrite(ref const console.LogEntry e) {
    auto id = idx(entryStart + entryCount);
    entries[id] = e;
    entryCache[id] = e.format(this).toStringz();

    auto total = entries.length.to!uint;
    if (entryCount == total) entryStart = idx(entryStart + 1);
    else entryCount = min(entryCount + 1, total);
  }

  override console.LogLevel logLevel() { return level; }
  override void logLevel(console.LogLevel value) { level = value; }

  private uint idx(uint value) {
    return value % entries.length;
  }
}
