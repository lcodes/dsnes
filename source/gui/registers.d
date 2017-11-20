module gui.registers;

import imgui;

import emulator.gui;

import cpu = snes.cpu;
import ppu = snes.ppu;

class RegistersWindow : Window {
  this() {
    super("I/O Registers".ptr);
  }

  protected override void draw() {
    auto cio = cpu.io;
    auto pio = ppu.io;

    // ImGui.Text("CPU"); ImGui.SameLine();
    // ImGui.Text("PPU"); ImGui.SameLine();
    // ImGui.Text("SMP");

    ImGui.Columns(6);
    ImGui.BeginGroup();
    ImGui.Text("$4200 NMITIMEN $%02x", cio.nmitimen); tooltip_NMITIMEN();
    ImGui.Text("$4201 WRIO     $%02x", cio.wrio);     tooltip("IO Port Write");
    ImGui.Text("$4202 WRMPYA   $%02x", cio.wrmpya);   tooltip("Multiplicand");
    ImGui.Text("$4203 WRMPYB   $%02x", cio.wrmpyb);   tooltip("Multiplicand");
    ImGui.Text("$4204 WRDIVL   $%02x", cio.wrdivl);   tooltip("Divisor & Dividend");
    ImGui.Text("$4205 WRDIVH   $%02x", cio.wrdivh);   tooltip("Divisor & Dividend");
    ImGui.Text("$4205 WRDIVB   $%02x", cio.wrdivb);   tooltip("Divisor & Dividend");
    ImGui.Text("$420b DMAEN    $%02x", cio.mdmaen);   tooltip("DMA Enable");
    ImGui.Text("$420b HDMAEN   $%02x", cio.hdmaen);   tooltip("HDMA Enable");
    ImGui.Text("$420d MEMSEL   $%02x", cio.memsel);   tooltip("ROM Speed");
    ImGui.EndGroup();
    ImGui.NextColumn();

    ImGui.BeginGroup();
    ImGui.Text("$2100 INIDISP  $%02x", pio.inidisp);
    ImGui.Text("$2101 OBSEL    $%02x", pio.obsel);
    ImGui.Text("$2102 OAMADDL  $%02x", pio.oamBaseAddress.l);
    ImGui.Text("$2102 OAMADDH  $%02x", pio.oamBaseAddress.h);
    ImGui.Text("$2105 BGMODE   $%02x", pio.bgmode);
    ImGui.Text("$2106 MOSAIC   $%02x", pio.mosaic);
    foreach (n; 0..4) {
      ImGui.Text("$210%x BG%uSC    $%02x", 7 + n, n, cast(ubyte) pio.bgScreenAddrs[n]);
    }
    ImGui.EndGroup();
    ImGui.NextColumn();

    ImGui.BeginGroup();
    ImGui.Text("$210b BG12NBA $%02x", cast(ubyte) pio.bgTileData[0]);
    ImGui.Text("$210c BG34NBA $%02x", cast(ubyte) pio.bgTileData[1]);
    foreach (n; 0..4) {
      ImGui.Text("$21%02x BG%uHOFS $%02x", 0xd + n * 2 + 0, n, pio.bgOffset[n].h);
      ImGui.Text("$21%02x BG%uVOFS $%02x", 0xd + n * 2 + 1, n, pio.bgOffset[n].v);
    }
    ImGui.EndGroup();
    ImGui.NextColumn();

    ImGui.BeginGroup();
    ImGui.Text("$2115 VMAIN   $%02x", pio.vmain);
    ImGui.Text("$2116 VMADDL  $%02x", pio.vramAddress.l);
    ImGui.Text("$2117 VMADDH  $%02x", pio.vramAddress.h);
    ImGui.Text("$211a M7SEL   $%02x", pio.m7sel);
    foreach (n; 0..6) {
      ImGui.Text("$21%02x M7%c     $%02x", 0x2b + n, n < 4 ? 'A' + n : 'X' + n - 4, pio.m7[n]);
    }
    ImGui.EndGroup();
    ImGui.NextColumn();

    ImGui.BeginGroup();
    ImGui.Text("$2121 CGADD    $%02x", pio.cgramAddress);
    ImGui.Text("$2123 W12SEL   $%02x", pio.w12sel);
    ImGui.Text("$2124 W34SEL   $%02x", pio.w34sel);
    ImGui.Text("$2125 WOBJSEL  $%02x", pio.wobjsel);
    foreach (n; 0..4) {
      ImGui.Text("$212%x WH%u      $%02x", 6 + n, n, pio.wh[n]);
    }
    ImGui.Text("$212a WBGLOG   $%02x", pio.wbglog);
    ImGui.Text("$212b WOBJLOG  $%02x", pio.wobjlog);
    ImGui.EndGroup();
    ImGui.NextColumn();

    ImGui.BeginGroup();
    ImGui.Text("$212c TM       $%02x", pio.tm);
    ImGui.Text("$212d TS       $%02x", pio.ts);
    ImGui.Text("$212e TMW      $%02x", pio.tmw);
    ImGui.Text("$212f TSW      $%02x", pio.tsw);
    ImGui.Text("$2130 CGWSEL   $%02x", pio.cgwsel);
    ImGui.Text("$2131 CGADDSUB $%02x", pio.cgaddsub);
    ImGui.Text("$2132 COLDATA  $%02x", pio.coldata);
    ImGui.Text("$2133 SETINI   $%02x", pio.setini);
    ImGui.EndGroup();
    ImGui.NextColumn();
  }
}

private:

void tooltip_NMITIMEN() {
  tooltip("Interrupt Enable");
}
