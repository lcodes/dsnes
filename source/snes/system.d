module snes.system;

import std.algorithm.comparison : min;

import std.bitmanip : bitfields;
import std.conv : to;

import emulator = emulator.system;
import thread   = emulator.thread;

public {
  import pak = snes.cartridge;
  import mem = snes.memory;
  import cpu = snes.cpu;
  import dsp = snes.dsp;
  import ppu = snes.ppu;
  import smp = snes.smp;
}

final class SNES : emulator.System {
  this() {
    mem.initialize();
    cpu.initialize();
    ppu.initialize();
    smp.initialize();
    dsp.initialize();
  }

  ~this() {
    dsp.terminate();
    smp.terminate();
    ppu.terminate();
    cpu.terminate();
    mem.terminate();
  }

override:
  string title() { return pak.title; }

  VideoSize videoSize() { return VideoSize(512, 480); }
  VideoSize videoSize(uint width, uint height, bool arc) {
    uint w = (256 * (arc ? 8.0 / 7.0 : 1)).to!uint;
    auto h = 240;
    auto m = min(width / w, height / h);
    return VideoSize(w * m, h * m);
  }

  uint videoColors() { return 1 << 19; }
  ulong videoColor(uint color) {
    // auto c = cast(Color) color;
    assert(0);
  }

  bool loaded() { return false; }
  void load(string file) { pak.load(file); }
  void save() { assert(0); }
  void unload() { assert(0); }

  void connect(uint port, uint device) { assert(0); }

  void power() {
    // configureVideoPalette();
    // configureVideoEffects();

    // TODO: random.seed

    thread.reset();

    cpu.power();
    smp.power();
    dsp.power();
    ppu.power();

    // if (pak.hasICD2) icd2.power();

    // peripherals.reset();
  }

  void run() {
    while (true) if (thread.run() == thread.Event.frame) ppu.refresh();
  }

  bool rtc() {
    // TODO
    return false;
  }

  void rtcSync() {
    
  }
}

struct Color {
  uint _; alias _ this;
  // mixin(bitfields!(ubyte, "r", 4,
  //                  ubyte, "unused1", 
  //                  ubyte, "g", 4,
  //                  ubyte, "b", 4,
  //                  ubyte, "l", 4));
}

// static assert(Color.sizeof == uint.sizeof);
