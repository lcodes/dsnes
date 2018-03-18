/**
 * Status bar displayed at the bottom of the native window.
 */
module gui.status;

import core.stdc.stdio  : snprintf;
import core.stdc.string : memmove;

import std.exception : assumeUnique;

import imgui;

import emulator.system : System;
import emulator.util   : cstring;
import platform = emulator.platform;

import gui.console : lastLogMessage;
import gui.layout  : fixedWindowFlags, statusBarHeight;

/// Status bar section. Register with addSection(). Call section() within.
alias Section = void function();

/// Registers a new status bar section. Appended if index is out of bounds.
void addSection(Section section, int index = -1) {
  if (index < 0 || index >= sections.length) {
    sections ~= section;
  }
  else {
    sections.length = sections.length + 1;

    auto ptr = sections.ptr + index;
    memmove(ptr + 1, ptr, sections.length - index);

    sections[index] = section;
  }

  if (layouts.length < sections.length) {
    layouts.length += 4;
  }
}

/// Internal section state from ticking a section to drawing it.
private struct Layout {
  ImVec4  color;
  cstring text;
  float   width;
  ushort  length;
  bool    flex;
}

private __gshared {
  char[32] cpuText;     /// Text buffer for CPU statistics.
  char[32] memText;     /// Text buffer for memory statistics.
  char[32] fpsText;     /// Text buffer for performance statistics.
  ubyte cpuLength;      /// Used length of the text buffer.
  ubyte memLength;      /// ditto

  Section[] sections;   /// Registered sections. Called every frame.
  Layout [] layouts;    /// Per-frame state captured by section().
  float availableWidth; /// Space remaining while going through sections.
  uint flexSections;    /// Number of flex sections this frame.
  uint drawnSectionId;  /// Index of the section currently being drawn.
  uint platformTick;    /// Poll platform statistics every time this cycles.
}

enum platformTickInterval = 60; /// Refresh platform statistics every second.

package void initialize() {
  addSection(&message);
  addSection(&debugger);
  addSection(&cpuUsage);
  addSection(&memoryUsage);
  addSection(&fps);

  platformTick = platformTickInterval - 1;
}

package void terminate() {
  sections = null;
}

/// Draws a status bar section. Negative width aligns left, otherwise right.
void section(string text, float width, bool flex = false) {
  section(ImGui.GetStyleColorVec4(ImGuiCol_Text), text, width, flex);
}
/// ditto
void section(ref const ImVec4 color, string text,
             float width, bool flex = false)
{
  auto s   = &layouts[drawnSectionId];
  s.color  = color;
  s.text   = text.ptr;
  s.length = cast(ushort) text.length;
  s.width  = width;
  s.flex   = flex;

  if (flex) {
    flexSections++;
  }
  else {
    availableWidth -= width;
  }
}

/// Displays the last console message.
void message() {
  auto msg = lastLogMessage();
  section(msg.ptr is null ? "" : msg, 250, true);
}

/// Displays the state of the debugger.
void debugger() {
  "STOPPED".section(100);
}

/// Displays CPU usage statistics.
void cpuUsage() {
  cpuText[0..cpuLength].assumeUnique.section(120);
}
void updateCpuUsage() {
  cpuLength = cast(ubyte) snprintf(cpuText.ptr, cast(uint) cpuText.length,
                                   "CPU %6.2f %%", platform.cpuUsage);
}

/// Displays memory usage statistics.
void memoryUsage() {
  memText[0..memLength].assumeUnique.section(140);
}
void updateMemoryUsage() {
  // import core.memory : GC;
  // memLength = cast(ubyte) snprintf(memText.ptr, cast(uint) memText.length,
                                   // "%d", GC.stats.usedSize);
  memLength = cast(ubyte) snprintf(memText.ptr, cast(uint) memText.length,
                                   "MEM %8.3f Mb", platform.memoryUsage);
}

/// Displays frame performance statistics.
void fps() {
  auto framerate = ImGui.GetIO().Framerate;
  auto length = snprintf(fpsText.ptr, cast(uint) fpsText.length,
                         "%.3f ms | %.1f FPS",
                         1000f / framerate, framerate);

  fpsText[0..length].assumeUnique.section(160);
}

/// Draws the main status bar at the bottom of the native window.
package void draw() {
  auto bg  = ImGui.GetColorU32(ImGuiCol_MenuBarBg);
  auto pad = ImVec2(ImGui.GetStyle.WindowPadding.x, 2);
  ImGui.PushStyleColor(ImGuiCol_WindowBg, bg);
  ImGui.PushStyleVar(ImGuiStyleVar_WindowMinSize,  ImVec2_zero);
  ImGui.PushStyleVar(ImGuiStyleVar_WindowPadding,  pad);
  ImGui.PushStyleVar(ImGuiStyleVar_WindowRounding, 0);

  statusBarHeight = ImGui.GetTextLineHeightWithSpacing();

  auto io   = &ImGui.GetIO();
  auto pos  = ImVec2(0, io.DisplaySize.y - statusBarHeight);
  auto size = ImVec2(io.DisplaySize.x, statusBarHeight);

  ImGui.SetNextWindowPos(pos);
  ImGui.SetNextWindowSize(size);
  ImGui.Begin("##MainStatusBar", null, fixedWindowFlags);

  availableWidth = size.x;
  drawSections();

  ImGui.End();
  ImGui.PopStyleVar(3);
  ImGui.PopStyleColor(1);
}

private:

void drawSections() {
  if (++platformTick == platformTickInterval) {
    platformTick = 0;
    updateCpuUsage();
    updateMemoryUsage();
  }

  // Accumulate the sections' draw state.
  flexSections   = 0;
  drawnSectionId = 0;

  foreach (section; sections) {
    section();
    drawnSectionId++;
  }

  // Resolve the width of flex sections.
  auto drawList  = layouts[0..sections.length];
  auto flexWidth = availableWidth / flexSections;

  foreach (ref section; drawList) {
    if (section.flex) {
      section.width = flexWidth;
    }
  }

  // Draw each section.
  auto textColor     = &ImGui.GetStyle().Colors[ImGuiCol_Text];
  auto lastTextColor = *textColor;

  float x = 0;
  foreach (ref section; drawList) {
    x += section.width;

    *textColor = section.color;

    ImGui.TextUnformatted(section.text, section.text + section.length);
    ImGui.SameLine(x);
  }

  *textColor = lastTextColor;
}
