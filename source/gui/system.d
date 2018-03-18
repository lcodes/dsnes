/**
 * Application GUI system. Contains high-level GUI functions.
 * See the emulator.gui module for low-level GUI functions.
 *
 * Wires all the GUI modules together.
 */
module gui.system;

import std.exception : enforce;

import imgui;

import emulator.profiler : Profile;

import gui.files;
import gui.game;
import gui.settings;

import gui.breakpoints;
import gui.console;
import gui.debugger;
import gui.profiler;

import gui.cpu;
import gui.ppu;
import gui.smp;

import gui.inputs;
import gui.memory;
import gui.registers;

import about  = gui.about;
import error  = gui.error;
import fonts  = gui.fonts;
import layout = gui.layout;
import menu   = gui.menu;
import status = gui.status;

/// List of window types to instantiate at launch.
enum windows = [
                typeid(ProfilerWindow),
                typeid(FilesWindow),
                typeid(GameWindow),
                typeid(SettingsWindow),
                typeid(BreakpointsWindow),
                typeid(ConsoleWindow),
                // typeid(DebuggerWindow),
                // typeid(ProfilerWindow),

                typeid(CpuWindow),
                typeid(PpuWindow),
                typeid(PpuWindow),

                typeid(InputsWindow),
                typeid(RegistersWindow),
                typeid(MemoryWindow)];

alias layout.windowT!FilesWindow filesWindow; ///
alias layout.windowT!GameWindow  gameWindow;  ///

void initialize() {
  layout.initialize(windows);
  menu.initialize();
  status.initialize();
}

void terminate() {
  status.terminate();
  menu.terminate();
  layout.terminate();
}

void draw() {
  scope auto p = new Profile!();

  about.draw();
  error.draw();

  fixedWindow!(menu.draw)  (layout.showMenu,   layout.menuBarHeight);
  fixedWindow!(status.draw)(layout.showStatus, layout.statusBarHeight);

  builtinWindow!(ImGui.ShowTestWindow)   (layout.showTest);
  builtinWindow!(ImGui.ShowMetricsWindow)(layout.showMetrics);

  layout.draw();
}

private:

void fixedWindow(alias draw)(bool show, ref float height) {
  if (show) {
    draw();
  }
  else {
    height = 0;
  }
}

void builtinWindow(alias draw)(ref bool show) {
  if (show) {
    draw(&show);
  }
}
