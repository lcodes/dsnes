module gui.ppu;

import imgui;

import emulator.gui;

import ppu = snes.ppu;

class PpuWindow : Window {
  this() {
    super("PPU".ptr);
  }

  protected override void draw() {
    ImGui.Text("Screen"); ImGui.SameLine();
    ImGui.Text("BG 1"); ImGui.SameLine();
    ImGui.Text("BG 2"); ImGui.SameLine();
    ImGui.Text("BG 3"); ImGui.SameLine();
    ImGui.Text("BG 4"); ImGui.SameLine();
    ImGui.Text("OAM"); ImGui.SameLine();
    ImGui.Text("CGRAM");
  }
}
