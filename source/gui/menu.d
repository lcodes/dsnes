/**
 * Menu bar displayed at the top of the native window.
 */
module gui.menu;

import std.algorithm : map, min, reduce, sort;
import std.path    : baseName, dirName;
import std.process : browse;
import std.string  : toStringz;

import imgui;

import emulator.util : cstring;
import system = emulator.system;

import about    = gui.about;
import layout   = gui.layout;
import settings = gui.settings;

/// Entry in the window menu tree. Generated from Window instances.
private struct WindowMenuEntry {
  WindowMenuEntry[] children;
  union {
    cstring label;
    layout.Window window;
  }

  this(cstring label) {
    this.label = label;
  }
  this(layout.Window window) {
    this.window = window;
  }

  int opCmp(ref const WindowMenuEntry rhs) {
    return this.order < rhs.order;
  }

  double order() const {
    return children.length
      ? children.map!"a.order".reduce!min
      : window.menuIndex;
  }
}

/// The window menu entries used by windowMenu().
private __gshared WindowMenuEntry[] windowMenuEntries;

/// Updates lookup with new submenu entries as needed. Returns the one for path.
private WindowMenuEntry* build(WindowMenuEntry[string] lookup, string path) {
  auto menu = path in lookup;
  if (menu !is null) {
    return menu;
  }

  lookup[path] = WindowMenuEntry(path.baseName.toStringz);

  menu = path in lookup;
  path = path.dirName;

  if (path.length > 1) {
    lookup.build(path).children ~= *menu;
  }

  return menu;
}

/// Sorts window menu entries and their children recursively.
private void reorder(ref WindowMenuEntry[] menu) {
  menu.sort();

  foreach (ref e; menu) {
    e.children.reorder();
  }
}

/// Generates the window menu entries from the registered layout windows.
void rebuildWindowMenu() {
  WindowMenuEntry[string] lookup;

  foreach (w; layout.windows) {
    if (!w.showInWindowMenu) {
      continue;
    }

    auto path = w.subMenuPath;
    auto menu = lookup.build(path);

    assert(menu !is null);
    menu.children ~= WindowMenuEntry(w);
  }

  windowMenuEntries = lookup.values;
  windowMenuEntries.reorder();
}

package:

/// Generates dynamic menu entries.
void initialize() {
  rebuildWindowMenu();
}

/// Cleans up dynamic menu entries.
void terminate() {
  windowMenuEntries = null;
}

/// Draws the main menu bar at the top of the native window.
void draw() {
  auto result = ImGui.BeginMainMenuBar();
  assert(result, "Failed to BeginMainMenuBar");

  subMenu!fileMenu  ("File");   // Application commands
  subMenu!editMenu  ("Edit");   // Emulator commands
  subMenu!viewMenu  ("View");   // GUI commands
  subMenu!debugMenu ("Debug");  // Developer commands
  subMenu!windowMenu("Window"); // List of available/opened windows
  subMenu!helpMenu  ("Help");   // Misc. commands

  layout.menuBarHeight = ImGui.GetWindowSize().y;

  ImGui.EndMainMenuBar();
}

private:

/// Helper to draw a top-level menu.
void subMenu(alias draw)(cstring label) {
  if (ImGui.BeginMenu(label)) {
    draw();
    ImGui.EndMenu();
  }
}

/// Shortcuts to re-open recently opened files.
void recentMenu() {
  if (system.recent.length == 0) {
    ImGui.MenuItem("No Recent Files", null, false, false);
  }
  else {
    foreach (n; 0..system.recent.length) {
      if (ImGui.MenuItem("Recent ROM")) {
        system.recent.open(n);
      }
    }

    ImGui.Separator();
    if (ImGui.MenuItem("Clear Recent List")) {
      system.recent.clear();
    }
  }
}

/// Application state commands.
void fileMenu() {
  auto enabled = system.isPowered;

  if (ImGui.MenuItem("Open File...")) {
    system.loader.open();
  }

  subMenu!recentMenu("Open Recent");

  ImGui.Separator();
  if (ImGui.MenuItem("Pause", null, false, enabled)) {
    // TODO
  }
  if (ImGui.MenuItem("Reset", null, false, enabled)) {
    // TODO
  }
  if (ImGui.MenuItem("Close", null, false, enabled)) {
    // TODO
  }

  ImGui.Separator();
  if (ImGui.MenuItem("Quick Save State", null, false, enabled)) {
    system.state.quickSave();
  }
  if (ImGui.MenuItem("Quick Load State", null, false, enabled)) {
    system.state.quickLoad();
  }
  if (ImGui.BeginMenu("Quick State Slot", enabled)) {
    foreach (n; 0..10) {
      if (ImGui.MenuItem("Slot #")) {
        system.state.quickSlot = n;
      }
    }
    ImGui.EndMenu();
  }
  if (ImGui.BeginMenu("Save State", enabled)) {
    foreach (n; 0..10) {
      if (ImGui.MenuItem("Slot #")) {
        system.state.save(n);
      }
    }
    ImGui.EndMenu();
  }
  if (ImGui.BeginMenu("Load State", enabled)) {
    foreach (n; 0..10) {
      if (ImGui.MenuItem("Slot #")) {
        system.state.load(n);
      }
    }
    ImGui.EndMenu();
  }

  ImGui.Separator();
  if (ImGui.MenuItem("Settings...")) {
    settings.show = true;
  }

  ImGui.Separator();
  if (ImGui.MenuItem("Quit")) {
    system.quit(0);
  }
}

/// GUI user interaction commands.
void editMenu() {
  if (ImGui.MenuItem("Undo")) {

  }
  if (ImGui.MenuItem("Redo")) {

  }

  ImGui.Separator();
  if (ImGui.MenuItem("Cut")) {

  }
  if (ImGui.MenuItem("Copy")) {

  }
  if (ImGui.MenuItem("Paste")) {

  }
  if (ImGui.MenuItem("Delete")) {

  }

  ImGui.Separator();
  if (ImGui.MenuItem("Select All")) {

  }
}

/// User interface control commands.
void viewMenu() {
  if (ImGui.MenuItem("Toggle Fullscreen")) {
    // TODO:
  }

  ImGui.Separator();
  if (ImGui.MenuItem("Zoom +")) {
    // TODO
  }
  if (ImGui.MenuItem("Zoom -")) {
    // TODO
  }
  if (ImGui.MenuItem("Reset zoom")) {
    // TODO
  }
  if (ImGui.MenuItem("Fit to screen")) {
    // TODO
  }

  ImGui.Separator();
  ImGui.MenuItem("Show Main Menu",  null, &layout.showMenu);
  ImGui.MenuItem("Show Status Bar", null, &layout.showStatus);
}

/// Emulator debugger control commands.
void debugMenu() {
  if (ImGui.MenuItem("Break")) {

  }
  if (ImGui.MenuItem("Step")) {

  }
  if (ImGui.MenuItem("Run to Cursor")) {

  }
  ImGui.Separator();
  if (ImGui.MenuItem("Set Breakpoint")) {

  }
  if (ImGui.MenuItem("Remove All Breakpoints")) {

  }
}

/// GUI windows management commands.
void windowMenu() {
  auto single = layout.isSingle;
  if (ImGui.MenuItem("Default", null, single)) {
    layout.setSingle(true);
  }
  if (ImGui.MenuItem("Developer", null, !single)) {
    layout.setSingle(false);
  }

  ImGui.Separator();

  // TODO: window tree
  foreach (window; layout.windows) {
    if (!window.showInWindowMenu) continue;

    ImGui.MenuItem(window.title, null, &window.open, !single);
  }

  ImGui.Separator();
  ImGui.MenuItem("GUI Metrics", null, &layout.showMetrics);
  ImGui.MenuItem("GUI Test",    null, &layout.showTest);
}

/// Miscellaneous application commands.
void helpMenu() {
  if (ImGui.MenuItem("Documentation...")) {
    browse("");
  }

  if (ImGui.MenuItem("Report Issue...")) {
    browse("");
  }

  ImGui.Separator();
  if (ImGui.MenuItem("Check for updates")) {
    // TODO
  }

  ImGui.Separator();
  ImGui.MenuItem("About...", null, &about.show);
}
