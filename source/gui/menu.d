module gui.menu;

import imgui;

import system = emulator.system;

import emulator.util : cstring;

import about    = gui.about;
import settings = gui.settings;

package void draw() {
  about   .draw();
  settings.draw();

  if (!ImGui.BeginMainMenuBar()) return;

  mainMenu!fileMenu("File");     // Application commands
  mainMenu!editMenu("Edit");     // Emulator commands
  mainMenu!viewMenu("View");     // GUI commands
  mainMenu!debugMenu("Debug");   // Developer commands
  mainMenu!windowMenu("Window"); // List of available/opened windows
  mainMenu!helpMenu("Help");     // Misc. commands

  ImGui.EndMainMenuBar();
}

private:

void mainMenu(alias draw)(cstring label) {
  if (ImGui.BeginMenu(label)) {
    draw();
    ImGui.EndMenu();
  }
}

void fileMenu() {
  if (ImGui.MenuItem("Open File...")) system.open();
  if (ImGui.BeginMenu("Open Recent")) {
    if (system.numRecentFiles == 0) {
      ImGui.MenuItem("No Recent Files", null, false, false);
    }
    else {
      foreach (n; 0..system.numRecentFiles) if (ImGui.MenuItem("Recent ROM")) system.openRecent(n);
      ImGui.Separator();
      if (ImGui.MenuItem("Clear Recent List")) system.clearRecentFiles();
    }
    ImGui.EndMenu();
  }

  auto enabled = system.isPowered;

  ImGui.Separator();
  if (ImGui.MenuItem("Quick Save State", null, false, enabled)) system.quickSaveState();
  if (ImGui.MenuItem("Quick Load State", null, false, enabled)) system.quickLoadState();
  if (ImGui.BeginMenu("Quick State Slot", enabled)) {
    foreach (n; 0..10) if (ImGui.MenuItem("Slot #")) system.quickStateSlot = n;
    ImGui.EndMenu();
  }
  if (ImGui.BeginMenu("Save State", enabled)) {
    foreach (n; 0..10) if (ImGui.MenuItem("Slot #")) system.saveState(n);
    ImGui.EndMenu();
  }
  if (ImGui.BeginMenu("Load State", enabled)) {
    foreach (n; 0..10) if (ImGui.MenuItem("Slot #")) system.loadState(n);
    ImGui.EndMenu();
  }

  ImGui.Separator();
  if (ImGui.MenuItem("Settings...")) settings.show = true;

  ImGui.Separator();
  if (ImGui.MenuItem("Quit")) system.quit();
}

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
  if (ImGui.MenuItem("Select All")) {
    
  }
}

void viewMenu() {
  
}

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

void windowMenu() {
  if (ImGui.MenuItem("Console")) {
    
  }
  if (ImGui.MenuItem("Debugger")) {
    
  }
  if (ImGui.MenuItem("Profiler")) {

  }

  ImGui.Separator();
  if (ImGui.MenuItem("CPU")) {
    
  }
  if (ImGui.MenuItem("PPU")) {
    
  }
  if (ImGui.MenuItem("SMP")) {
    
  }

  ImGui.Separator();
  if (ImGui.MenuItem("I/O")) {
    
  }
  if (ImGui.MenuItem("Memory")) {
    
  }
  if (ImGui.MenuItem("VRAM")) {
    
  }

  ImGui.Separator();
  if (ImGui.MenuItem("Inputs")) {
    
  }
}

void helpMenu() {
  if (ImGui.MenuItem("About...")) about.show = true;
}
