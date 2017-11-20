module gui.files;

import std.conv   : to;
import std.file   : SpanMode, dirEntries;
import std.string : toStringz;

import imgui;

import emulator.util : cstring;
import emulator.gui  : Window;

import system = emulator.system;

class FilesWindow : Window {
  this() {
    super("Files".ptr);
    refresh();
  }

  protected override void draw() {
    if (ImGui.Button("Refresh")) refresh();
    ImGui.Separator();

    foreach (ref const file; files) {
      ImGui.TextUnformatted(file.name);
      if (ImGui.IsItemClicked()) system.open(file.name.to!string);
    }
  }

private:

  void refresh() {
    files = null;

    foreach (f; "files".dirEntries(SpanMode.depth)) {
      files ~= FileInfo(f.name.toStringz);
    }
  }

  FileInfo[] files;

  static struct FileInfo {
    cstring name;
    cstring region;
    cstring features;
    cstring lastPlayed;
  }
}
