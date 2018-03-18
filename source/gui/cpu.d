module gui.cpu;

import std.conv   : to;
import std.traits : EnumMembers;

import imgui;

import emulator.util : cstring;
import emulator.gui  : tooltip;
import system = emulator.system;

import disasm : disasm;
import cpu = snes.cpu;

import gui.layout : Window;

immutable pflagTips =
  ["Carry", "Zero", "IRQ Disable", "Decimal",
   "Index register size (0 = 16-bit, 1 = 8-bit)",
   "Accumulator register size (0 = 16-bit, 1 = 8-bit)",
   "Overflow", "Negative"];

class CpuWindow : Window {
  enum Reg {
    A,
    X,
    Y,
    S,
    DP,
    PB,
    PC,
    DB
  }

  enum P { C, Z, I, D, X, M, V, N }

  private {
    cpu.Registers regs;
    ubyte db;

    ImVec4 defaultColor;
    ImVec4* color;
  }

  this() {
    super("CPU".ptr);

    color = &ImGui.GetStyle().Colors[ImGuiCol_Text];
    defaultColor = *color;
  }

  protected override void draw() {
    auto r = cpu.registers;

    // P-Flag
    ImGui.BeginGroup();
    foreach (p; EnumMembers!P) {
      enum c = p.to!string()[0];
      enum b = 1 << p;
      setColor((r.p & b) != (regs.p & b));
      (regs.p & b ? &ImGui.Text : &ImGui.TextDisabled)("%c", c);
      resetColor();
      tooltip(pflagTips[p]);
    }

    // Emulation Flag
    setColor(r.e != regs.e);
    (regs.e ? &ImGui.Text : &ImGui.TextDisabled)("E");
    resetColor();
    tooltip("6502 Emulation Mode");
    ImGui.EndGroup();

    // Registers
    ImGui.SameLine();
    ImGui.BeginGroup();
    setColor(r.a != regs.a); ImGui.Text("A  $%04x", regs.a.w); resetColor();
    tooltip("Accumulator");
    setColor(r.x != regs.x); ImGui.Text("X  $%04x", regs.x.w); resetColor();
    tooltip("X Index");
    setColor(r.y != regs.y); ImGui.Text("Y  $%04x", regs.y.w); resetColor();
    tooltip("Y Index");
    setColor(r.s != regs.s); ImGui.Text("SP $%04x", regs.s.w); resetColor();
    tooltip("Stack Pointer");
    setColor((r.pc & 0x00_ffff) != (regs.pc & 0x00_ffff));
    ImGui.Text("PC $%04x", regs.pc.w);
    resetColor();
    tooltip("Program Counter");
    setColor((r.pc & 0xff_0000) != (regs.pc & 0xff_0000));
    ImGui.Text("PB $  %02x", regs.pc.b);
    resetColor();
    // tooltip("Program Bank");
    // setColor(r.d != regs.d); ImGui.Text("DP $  %02x", cpu.getDP); resetColor();
    tooltip("Direct Page");
    setColor(r.b != regs.b); ImGui.Text("DB $  %02x", regs.b); resetColor();
    tooltip("Data Bank");
    ImGui.EndGroup();

    // Disassembly
    auto size = ImVec2(0, -ImGui.GetItemsLineHeightWithSpacing());
    ImGui.SameLine();
    ImGui.BeginChild("##scrolling", size);
    if (system.isPowered) {
      ImVec2 avail = ImGui.GetContentRegionAvail();

      char[43] str = void;
      uint addr = cpu.registers.pc;

      foreach (n; 0..avail.y / ImGui.GetTextLineHeightWithSpacing() - 1) {
        auto ret = disasm(addr, str);
        str[ret.length] = '\0';
        ImGui.TextUnformatted(ret.ptr);
      }
    }
    ImGui.EndChild();

    // Status Line
    // ImGui.Separator();
    // ImGui.Text("Hello!");

    regs = *r;
    // db = cpu.getDP;
  }

private:
  void setColor(bool changed) { *color = changed ? ImVec4(1, 0, 0, 1) : defaultColor; }

  void resetColor() { *color = defaultColor; }
}
