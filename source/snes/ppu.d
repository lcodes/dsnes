/**
 * Picture Processing Unit
 *
 * References:
 *   https://gitlab.com/higan/higan/blob/master/higan/sfc/ppu/
 *   https://wiki.superfamicom.org/snes/show/Registers
 */
module snes.ppu;

import std.bitmanip : BitArray, bitfields;

import emulator.util : bits;

import system = emulator.system;
import thread = emulator.thread;
import video  = emulator.video;

import emulator.types;

import cpu = snes.cpu;
import mem = snes.memory;
import smp = snes.smp;

debug {
  import core.stdc.stdio : printf;

  // debug = PPU;
  // debug = PPU_IO;
  // debug = PPU_BG;
  // debug = PPU_OBJ;
  // debug = PPU_WND;
  // debug = PPU_SCR;
  // debug = PPU_MEM;
}

const(IO)* io() nothrow @nogc { return &_io; }

// State
// -------------------------------------------------------------------------------------------------

enum {
  pitch  = 512,
  width  = 512,
  height = 480
}

private mixin Counter!scanline;

private __gshared {
  thread.Processor proc;

  Display display;
  PPU ppu1, ppu2;
  Latches latch;
  IO _io;
  Background bg1, bg2, bg3, bg4;
  Obj obj;
  Window window;
  Screen screen;
  VRAM vram;
  uint[width * height * uint.sizeof] output;
}

struct Display {
  bool interlace;
  bool overscan;
}

struct PPU {
  ubyte _version;
  ubyte mdr;
}

struct Latches {
  ushort vram;
  ubyte oam;
  ubyte cgram;
  ubyte bgofs;
  ubyte mode7;
  bool counters;
  bool hcounter;
  bool vcounter;

  ushort oamAddress;
  ubyte cgramAddress;
  bool cgramAddressUse;
}

struct VRAM {
  uint mask = 0x7fff;

  ref ushort opIndex(uint addr) nothrow @nogc {
    return (cast(ushort*) mem.vram.ptr)[addr & mask];
  }
}

// Public Helpers
// -------------------------------------------------------------------------------------------------

nothrow @nogc {
  bool interlace() { return display.interlace; }
  bool overscan() { return display.overscan; }
  uint vdisp() { return _io.overscan ? 240 : 225; }

  thread.Processor processor() { return proc; }
}

// Core
// -------------------------------------------------------------------------------------------------

package void initialize() {
  ppuCounter.initialize();
}

package void terminate() {
  ppuCounter.terminate();
}

package void power() {
  debug (PPU) printf("ppu.power\n");
  // TODO:
  // ppu1.version = 1;
  // ppu2.version = 3;
  // vram.mask = 0xff;
  // if (vram.mask != 0xffff) vram.mask = 0x7fff;

  proc = thread.create(&entry, system.colorburst * 6.0);
  ppuCounter.reset();
  output[] = uint.init;
}

private void entry() {
  while (true) {
    thread.synchronize();
    run();
  }
}

private void run() {
  debug (PPU) printf("ppu.entry\n");
  scanline();
  step(28);
  bg1.begin();
  bg2.begin();
  bg3.begin();
  bg4.begin();

  enum clocks = 1052 + 14 + 136;

  if (vcounter > 239) {
    step(clocks);
  }
  else {
    foreach (pixel; -7 .. 255) {
      bg1.run(1);
      bg2.run(1);
      bg3.run(1);
      bg4.run(1);
      step(2);

      bg1.run(0);
      bg2.run(0);
      bg3.run(0);
      bg4.run(0);
      if (pixel >= 0) {
        obj.run();
        window.run();
        screen.run();
      }
      step(2);
    }

    step(14);
    obj.tilefetch();
  }

  step(lineclocks - clocks);
}

nothrow @nogc {
  void refresh() {
    debug (PPU) printf("ppu.refresh\n");
    auto o = output.ptr;
    if (!overscan) o -= 14 * width;
    video.refresh(o, pitch * uint.sizeof, width, height);
  }

  private:

  void step(uint clocks) {
    debug (PPU) printf("ppu.step %u\n", clocks);
    clocks >>= 1;

    while (clocks--) {
      tick(2);
      processor.step(2);
      processor.synchronize(cpu.processor);
    }
  }

  void scanline() {
    debug (PPU) printf("ppu.scanline\n");
    if (vcounter == 0) {
      frame();
      bg1.frame();
      bg2.frame();
      bg3.frame();
      bg4.frame();
    }

    bg1.scanline();
    bg2.scanline();
    bg3.scanline();
    bg4.scanline();
    obj.scanline();
    window.scanline();
    screen.scanline();

    if (vcounter == 241) thread.yield(thread.Event.frame);
  }

  void frame() {
    debug (PPU) printf("ppu.frame\n");

    obj.frame();
    display.interlace = _io.interlace;
    display.overscan  = _io.overscan;
  }
}

// PPU Counter
// -------------------------------------------------------------------------------------------------

package mixin template Counter(alias scanline) {
pragma(inline, true) nothrow @nogc:

  void tick() {
    status.hcounter += 2; // Increment by smallest unit of time
    if (status.hcounter >= 1360 && status.hcounter == lineclocks) {
      status.hcounter = 0;
      vcounterTick();
    }

    history.index = (history.index + 1) & 2047;
    history.field   [history.index] = status.field;
    history.vcounter[history.index] = status.vcounter;
    history.hcounter[history.index] = status.hcounter;
  }

  void tick(uint clocks) {
    status.hcounter += clocks;
    if (status.hcounter >= lineclocks) {
      status.hcounter -= lineclocks;
      vcounterTick();
    }
  }

  bool field() { return status.field; }
  ushort vcounter() { return status.vcounter; }
  ushort hcounter() { return status.hcounter; }

  bool field(uint offset) { return history.field[offset.historyIndex]; }
  ushort vcounter(uint offset) { return history.vcounter[offset.historyIndex]; }
  ushort hcounter(uint offset) { return history.hcounter[offset.historyIndex]; }

  ushort hdot() {
    assert(0, "TODO");
  }

  ushort lineclocks() {
    // TODO:
    return /* system.region == system.Region.NTSC &&*/
      !status.interlace && vcounter == 240 && field == 1 ? 1360 : 1364;
  }

  struct ppuCounter { @disable this(); static:
    void initialize() {
      history.field.length = 2048;
    }

    void terminate() {
      history.field.length = 0;
    }

    nothrow @nogc:

    void reset() {
      status.interlace = false;
      status.field     = 0;
      status.vcounter  = 0;
      status.hcounter  = 0;
      history.index    = 0;

      foreach (n; 0..2048) history.field[n] = false;
      history.vcounter[] = 0;
      history.hcounter[] = 0;
    }

    void serialize() {
      assert(0);
    }
  }

private:
  uint historyIndex(uint offset) {
    return (history.index - (offset >> 1)) & 2047;
  }

  void vcounterTick() {
    import ppu = snes.ppu;
    if (++status.vcounter == 128) status.interlace = ppu.interlace();

    // TODO: region
    if ((!status.interlace && status.vcounter == 262) ||
        ( status.interlace && status.vcounter == 263) ||
        ( status.interlace && status.vcounter == 262 && status.field == 1))
    {
      status.vcounter = 0;
      status.field = !status.field;
    }
    scanline();
  }

  struct Status {
    ushort vcounter;
    ushort hcounter;
    bool   interlace;
    bool   field;
  }

  struct History {
    ushort[2048] vcounter;
    ushort[2048] hcounter;
    BitArray field;
    uint index;
  }

  __gshared Status status;
  __gshared History history;
}

// Background
// -------------------------------------------------------------------------------------------------

struct Background {
  IO io;
  Latch latch;
  Output output;
  Mosaic mosaic;
  int x, y;
  uint tileCounter;
  uint tile;
  uint priority;
  uint paletteNumber;
  uint paletteIndex;
  Data[2] data;
  ID id;

  static union Data {
    uint d; alias d this;
    struct { ushort l, h; }
  }

  static struct IO {
    ushort tiledataAddress;
    ushort screenAddress;
    ubyte screenSize;
    ubyte mosaic;
    bool tileSize;
    uint mode;
    uint[2] priority;

    bool aboveEnable;
    bool belowEnable;

    ushort hoffset;
    ushort voffset;
  }

  static struct Latch {
    ushort hoffset;
    ushort voffset;
  }

  static struct Output {
    static struct Pixel {
      uint priority; // 0 = None (transparent)
      ushort tile;
      ubyte palette;
    }
    Pixel above, below;
  }

  static struct Mosaic {
    Output.Pixel pixel; alias pixel this;
    uint vcounter;
    uint voffset;
    uint hcounter;
    uint hoffset;
  }

  enum ID { BG1, BG2, BG3, BG4 }

  enum Mode { bpp2, bpp4, bpp8, mode7, inactive }
  enum ScreenSize { size32x32, size32x64, size64x32, size64x64 }
  enum TileSize { size8x8, size16x16 }
  enum Screen { above, below }

  static union ScreenAddress {
    ubyte _; alias _ this;
    mixin(bitfields!(ubyte, "baseAddr", 6,
                     ubyte, "size",     2));
  }

  static union TileData {
    ubyte _; alias _ this;
    mixin(bitfields!(ubyte, "a", 4,
                     ubyte, "b", 4));
  }

  nothrow @nogc:

  ushort voffset() { return io.mosaic ? latch.voffset : io.voffset; }
  ushort hoffset() { return io.mosaic ? latch.hoffset : io.hoffset; }

  // V = 0, H = 0
  void frame() {}

  // H = 0
  void scanline() {}

  // H = 28
  void begin() {
    debug (PPU_BG) printf("ppu.bg.begin\n");
    auto hires = _io.bgMode == 5 || _io.bgMode == 6;
    x = -7;
    y = vcounter;

    if (y == 1) {
      mosaic.vcounter = io.mosaic + 1;
      mosaic.voffset = 1;
      latch.hoffset = io.hoffset;
      latch.voffset = io.voffset;
    }
    else if (--mosaic.vcounter == 0) {
      mosaic.vcounter = io.mosaic + 1;
      mosaic.voffset += io.mosaic + 1;
      latch.hoffset = io.hoffset;
      latch.voffset = io.voffset;
    }

    tileCounter = (7 - (latch.hoffset & 7)) << hires;
    data[0] = data[1] = 0;

    if (io.mode == Mode.mode7) return beginMode7();
    if (io.mosaic == 0) {
      latch.hoffset = io.hoffset;
      latch.voffset = io.voffset;
    }
  }

  void run(bool screen) {
    debug (PPU_BG) printf("ppu.bg.run [screen=%b]\n", screen);
    if (vcounter == 0) return;
    auto hires = _io.bgMode == 5 || _io.bgMode == 6;

    if (screen == Screen.below) {
      output.above.priority = 0;
      output.below.priority = 0;
      if (!hires) return;
    }

    if (tileCounter-- == 0) {
      tileCounter = 7;
      getTile();
    }

    if (io.mode == 7) return runMode7();

    auto palette = getTileColor();
    if (x == 0) mosaic.hcounter = 1;
    if (x >= 0 && --mosaic.hcounter == 0) {
      mosaic.hcounter = io.mosaic + 1;
      mosaic.priority = priority;
      mosaic.palette = palette ? cast(ubyte) (paletteIndex + palette) : 0;
      mosaic.tile = cast(ushort) tile;
    }
    if (screen == Screen.above) x++;
    if (mosaic.palette == 0) return;

    if ((!hires || screen == Screen.above) && io.aboveEnable) output.above = mosaic;
    if ((!hires || screen == Screen.below) && io.belowEnable) output.below = mosaic;
  }

  void getTile() {
    debug (PPU_BG) printf("ppu.bg.getTile\n");
    auto hires = _io.bgMode == 5 || _io.bgMode == 6;

    auto colorDepth = io.mode == Mode.bpp2 ? 0 : io.mode == Mode.bpp4 ? 1 : 2;
    auto paletteOffset = _io.bgMode == 0 ? id << 5 : 0;
    auto paletteSize = 2 << colorDepth;
    auto tileMask = vram.mask >> (3 + colorDepth);
    auto tiledataIndex = io.tiledataAddress >> (3 + colorDepth);

    auto tileHeight = io.tileSize == TileSize.size8x8 ? 3 : 4;
    auto tileWidth = hires ? 4 : tileHeight;

    auto w = 256 << hires;

    auto hmask = tileHeight == 3 ? w : w << 1;
    auto vmask = hmask;
    if (io.screenSize & 1) hmask <<=1;
    if (io.screenSize & 2) vmask <<=1;
    hmask--;
    vmask--;

    auto px = x << hires;
    auto py = io.mosaic == 0 ? y : mosaic.voffset;

    auto hscroll = hoffset;
    auto vscroll = voffset;
    if (hires) {
      hscroll <<=1;
      if (_io.interlace) py = (py << 1) + field;
    }

    auto hofs = hscroll + px;
    auto vofs = vscroll + py;

    if (_io.bgMode == 2 || _io.bgMode == 4 || _io.bgMode == 6) {
      auto offsetX = x + (hscroll & 7);

      if (offsetX >= 8) {
        auto hval = bg3.getTile((offsetX - 8) + (bg3.hoffset & ~7), bg3.voffset + 0);
        auto vval = bg3.getTile((offsetX - 8) + (bg3.hoffset & ~7), bg3.voffset + 8);
        auto validMask = id == ID.BG1 ? 0x2000 : 0x4000;

        if (_io.bgMode == 4) {
          if (hval & validMask) {
            if ((hval & 0x8000) == 0) {
              hofs = offsetX + (hval & ~7);
            }
            else {
              vofs = y + hval;
            }
          }
        }
        else {
          if (hval & validMask) hofs = offsetX + (hval & ~7);
          if (vval & validMask) vofs = y + vval;
        }
      }
    }

    hofs &= hmask;
    vofs &= vmask;

    auto screenX = io.screenSize & 1 ? 32 << 5 : 0;
    auto screenY = io.screenSize & 2 ? 32 << 5 : 0;
    if (io.screenSize == 3) screenY <<= 1;

    auto tx = hofs >> tileWidth;
    auto ty = vofs >> tileHeight;

    auto offset = ((ty & 0x1f) << 5) + (tx & 0x1f);
    if (tx & 0x20) offset += screenX;
    if (ty & 0x20) offset += screenY;

    auto address = io.screenAddress + offset;
    tile = vram[address];
    auto mirrorX = tile & 0x4000;
    auto mirrorY = tile & 0x8000;
    priority = io.priority[(tile & 0x2000) != 0];
    paletteNumber = (tile >> 10) & 7;
    paletteIndex = paletteOffset + (paletteNumber << paletteSize);

    if (tileWidth  == 4 && cast(bool) (hofs & 8) != mirrorX) tile +=  1;
    if (tileHeight == 4 && cast(bool) (vofs & 8) != mirrorY) tile += 16;
    auto character = ((tile & 0x03ff) + tiledataIndex) & tileMask;

    if (mirrorY) vofs ^= 7;
    offset = (character << (3 + colorDepth)) + (vofs & 7);

    switch (io.mode) {
    default: assert(0);
    case Mode.bpp8:
      data[1].h = vram[offset + 24];
      data[1].l = vram[offset + 16];
      goto case;
    case Mode.bpp4:
      data[0].h = vram[offset + 8];
      goto case;
    case Mode.bpp2:
      data[0].l = vram[offset + 0];
    }

    if (mirrorX) {
      foreach (n; 0..2) {
        data[n] = ((data[n] >> 4) & 0x0f0f0f0f) | ((data[n] << 4) & 0xf0f0f0f0);
        data[n] = ((data[n] >> 2) & 0x33333333) | ((data[n] << 2) & 0xcccccccc);
        data[n] = ((data[n] >> 1) & 0x55555555) | ((data[n] << 1) & 0xaaaaaaaa);
      }
    }
  }

  uint getTile(uint x, uint y) {
    debug (PPU_BG) printf("ppu.bg.getTile x=%u y=%u\n", x, y);
    auto hires = _io.bgMode == 5 || _io.bgMode == 6;
    auto tileHeight = io.tileSize == TileSize.size8x8 ? 3 : 4;
    auto tileWidth = hires ? 4 : tileHeight;
    auto w = hires ? width : width >> 1;
    auto maskX = tileHeight == 3 ? w : w << 1;
    auto maskY = maskX;
    if (io.screenSize & 1) maskX <<= 1;
    if (io.screenSize & 2) maskY <<= 1;
    maskX--;
    maskY--;

    auto screenX = io.screenSize & 1 ? 32 << 5 : 0;
    auto screenY = io.screenSize & 2 ? 32 << 5 : 0;
    if (io.screenSize == 3) screenY <<= 1;

    x = (x & maskX) >> tileWidth;
    y = (y & maskY) >> tileHeight;

    auto offset = ((y & 0x1f) << 5) + (x & 0x1f);
    if (x & 0x20) offset += screenX;
    if (y & 0x20) offset += screenY;

    auto address = io.screenAddress + offset;
    return vram[address];
  }

  uint getTileColor() {
    debug (PPU_BG) printf("ppu.bg.getTileColor\n");
    uint color;
    switch (io.mode) {
    default: assert(0);
    case Mode.bpp8:
      color += data[1] >> 24 & 0x80;
      color += data[1] >> 17 & 0x40;
      color += data[1] >> 10 & 0x20;
      color += data[1] >>  3 & 0x10;
      data[1] <<= 1;
      goto case;
    case Mode.bpp4:
      color += data[0] >> 28 & 0x08;
      color += data[0] >> 21 & 0x04;
      goto case;
    case Mode.bpp2:
      color += data[0] >> 14 & 0x02;
      color += data[0] >>  7 & 0x01;
      data[0] <<= 1;
    }
    return color;
  }

  // Mode 7

  int clip(int n) {
    // 13-bit sign extend: --s---nnnnnnnnnn -> ssssssnnnnnnnnnn
    return n & 0x2000 ? (n | ~1023) : (n & 1023);
  }

  void beginMode7() {
    debug (PPU_BG) printf("ppu.bg.beginMode7\n");
    // H = 28
    // latch.hoffset = io.hoffsetMode7;
    // latch.voffset = io.voffsetMode7;
    assert(0);
  }

  void runMode7() {
    debug (PPU_BG) printf("ppu.bg.runMode7\n");
    auto a = cast(short) _io.m7a;
    auto b = cast(short) _io.m7b;
    auto c = cast(short) _io.m7c;
    auto d = cast(short) _io.m7d;

    auto cx = cast(short) _io.m7y;
    auto cy = cast(short) _io.m7x;
    auto hofs = cast(short) latch.hoffset;
    auto vofs = cast(short) latch.voffset;

    if (x++ & ~255) return;
    auto x = mosaic.hoffset;
    auto y = bg1.mosaic.voffset; // BG2 vertical mosaic uses BG1 mosaic size.

    if (--mosaic.hcounter == 0) {
      mosaic.hcounter = io.mosaic + 1;
      mosaic.hoffset += io.mosaic + 1;
    }

    // if (io.hflipMode7) x = 0xff - x;
    // if (io.vflipMode7) y = 0xff - y;

    auto psx = ((a * clip(hofs - cx)) & ~63) + ((b * clip(vofs - cy)) & ~63) + ((b * y) & ~63) + (cx << 8);
    auto psy = ((c * clip(hofs - cx)) & ~63) + ((d * clip(vofs - cy)) & ~63) + ((d * y) & ~63) + (cy << 8);

    auto px = psx + (a * x);
    auto py = psy + (c * x);

    // Mask pseudo-FP bits.
    px >>= 8;
    py >>= 8;

    uint tile;
    uint palette;
    switch (0) {
    // switch (io.repeatMode7) {
    case 0:
    case 1:
      // Screen repetition outside of screen area.
      px &= 1023;
      py &= 1023;
      tile = vram[(py >> 3) * 128 + (px >> 3)] & 0xff;
      palette = vram[(tile << 6) + ((py & 7) << 3) + (px & 7)] >> 8;
      break;

    case 2:
      // Palette color 0 outside of screen area.
      if ((px | py) & ~1023) {
        palette = 0;
      }
      else {
        px &= 1023;
        py &= 1023;
        tile = vram[(py >> 3) * 128 + (px >> 3)] & 0xff;
        palette = vram[(tile << 6) + ((py & 7) << 3) + (px & 7)] >> 8;
      }
      break;

    case 3:
      // Character 0 repetition outside of screen area.
      if ((px | py) & ~1023) {
        tile = 0;
      }
      else {
        px &= 1023;
        py &= 1023;
        tile = vram[(py >> 3) * 128 + (px >> 3)] & 0xff;
      }
      palette = vram[(tile << 6) + ((py & 7) << 3) + (px & 7)] >> 8;
      break;

    default: assert(0);
    }

    uint priority;
    if (id == ID.BG1) {
      priority = io.priority[0];
    }
    else {
      priority = io.priority[(palette & 0x80) != 0];
      palette &= 0x7f;
    }

    if (palette == 0) return;

    if (io.aboveEnable) {
      output.above.palette = cast(ubyte) palette;
      output.above.priority = priority;
      output.above.tile = 0;
    }

    if (io.belowEnable) {
      output.below.palette = cast(ubyte) palette;
      output.above.priority = priority;
      output.below.tile = 0;
    }
    assert(0);
  }
}

// Object
// -------------------------------------------------------------------------------------------------

struct OAM {
  Obj[128] objects;

  static struct Obj {
    uint dimension(bool width)() {
      assert(0);
      // if (size == 0) {
      //   static if (!width) if (io.interlace && io.baseSize >= 6) return 16; // Hardware quirk.

      //   switch (io.baseSize) {
      //   case 0: case 1: case 2:         return 8;
      //   case 3: case 4: case 6: case 7: return 16;
      //   case 5:                         return 32;
      //   default: assert(0);
      //   }
      // }
      // else {
      //   switch (io.baseSize) {
      //   case 0:                         return 16;
      //   case 1: case 3: case 6: case 7: return 32;
      //   case 2: case 4: case 5:         return 64;
      //   default: assert(0);
      //   }
      // }
    }

    alias width  = dimension!true;
    alias height = dimension!false;

    // mixin(bitfields!(ubyte, "x",          9,
    //                  ubyte, "y",          8,
    //                  ubyte, "character",  8,
    //                  bool,  "nameselect", 1,
    //                  bool,  "vflip",      1,
    //                  bool,  "hflip",      1,
    //                  ubyte, "priority",   2,
    //                  ubyte, "palette",    3,
    //                  bool,  "size",       1));
  }

  nothrow @nogc:

  ubyte read(ushort addr) {
    debug (PPU_OBJ) printf("ppu.obj.read $%04x\n", addr);
    if (addr & (1 << 9)) {
      
    }
    else {
      auto n = addr >> 2; // object #
      addr &= 3;
      switch (addr) {
      // case 0: return objects[n].x;
      // case 1: return objects[n].y;
      // case 2: return objects[n].character;
      default:
      }
      // if (addr == 0) return 
      // if (addr == 1)
    }

    assert(0);
  }

  void write(ushort addr, ubyte data) {
    debug (PPU_OBJ) printf("ppu.obj.write $%04x = $02x\n", addr, data);
    assert(0);
  }
}

struct Obj {
  OAM oam;
  State t;
  Output output;

  static struct Item {
    mixin(bitfields!(bool,  "valid", 1,
                     ubyte, "index", 7));
  }

  static struct Tile {
    // TODO
  }

  static struct State {
    uint x;
    uint y;
    uint itemCount;
    uint tileCount;
    Item[2][32] item;
    Tile[2][34] tile;
  }

  static struct Output {
    static struct Pixel {
      mixin(bitfields!(uint,  "priority", 24,
                       ubyte, "palette",   8));
    }
    Pixel above, below;
  }

  nothrow @nogc:

  void addressReset() {}
  void setFirstSprite() {}

  void frame() {}

  void scanline() {}
  void run() {}
  void tilefetch() {}
  void power() {}

  void onScanline(ref OAM.Obj obj) {
  }

  void serialize() {
    assert(0);
  }
}

// Window
// -------------------------------------------------------------------------------------------------

struct Window {
  uint x;
  Output output;

  static struct Output {
    static struct Pixel {
      bool colorEnable;
    }

    Pixel above, below;
  }

  nothrow @nogc:

  void scanline() { x = 0; }

  void run() {
    debug (PPU_WND) printf("ppu.window.run\n");
    // auto one = x >= io.oneLeft && x <= io.oneRight;
    // auto two = x >= io.twoLeft && x <= io.twoRight;
    x++;

    // TODO: io
    // assert(0);
  }

  bool test(bool oneEnable, bool one, bool twoEnable, bool two, uint mask) {
    if (!oneEnable) return two && twoEnable;
    if (!twoEnable) return one;
    if (mask == 0) return one | one;
    if (mask == 1) return one & one;
    return (one ^ two) == 3 - mask;
  }

  void power() {
    debug (PPU_WND) printf("ppu.window.power\n");
    // TODO: io registers

    output.above.colorEnable = 0;
    output.below.colorEnable = 0;

    x = 0;
  }

  void serialize() { assert(0); }
}

// Screen
// -------------------------------------------------------------------------------------------------

struct Screen {
  ushort[0x100] cgram;

  Math math;

  uint* lineA;
  uint* lineB;

  static struct Math {
    static struct Screen {
      mixin(bitfields!(ushort, "color",       15,
                       bool,   "colorEnable",  1));
    }

    Screen above, below;

    mixin(bitfields!(bool, "transparent", 1,
                     bool, "blendMode",   1,
                     bool, "colorHalve",  1,
                     byte, "__padding",   5));
  }

  nothrow @nogc:

  void scanline() {
    debug (PPU_SCR) printf("ppu.screen.scanline\n");
    lineA = output.ptr + vcounter * width * 2;
    lineB = lineA + (display.interlace ? 0 : width);

    // The first hires pixel of each scanline is transparent.
    math.above.color = paletteColor(0);
    math.below.color = math.above.color;

    // math.above.colorEnable = (window.io.col.aboveMask & 1) == 0;
    // math.below.colorEnable = (window.io.col.belowMask & 1) == 0;

    math.transparent = true;
    math.blendMode = false;
    // math.colorHalve = io.colorHalve && !io.blendMode && math.above.colorEnable;
    // assert(0);
  }

  void run() {
    debug (PPU_SCR) printf("ppu.screen.run\n");
    if (vcounter == 0) return;

    // auto hires = .io.pseudoHires || .io.bgMode == 5 || .io.bgMode == 6;
    // auto belowColor = below(hires);
    // auto aboveColor = above();

    // *lineA++ = *lineB++ = io.displayBrightness << 15 | (hires ? belowColor : aboveColor);
    // *lineA++ = *lineB++ = io.displayBrightness << 15 | (aboveColor);
    // assert(0);
  }

  ushort below(bool hires) {
    debug (PPU_SCR) printf("ppu.screen.below hires=%b\n", hires);
    // if (io.displayDisable || (!io.overscan && vcounter >= 255)) return 0;

    uint priority;
    if (bg1.output.below.priority) {
      priority = bg1.output.below.priority;
      // if (io.directColor && (io.bgMode == 3 || io.bgMode == 4 || io.bgMode == 7)) {
      //   math.below.color = directColor(bg1.output.below.palette, bg1.output.below.tile);
      // }
      // else {
      //   math.below.color = paletteColor(bg1.otput.below.palette);
      // }
    }
    if (bg2.output.below.priority > priority) {
      priority = bg2.output.below.priority;
      math.below.color = paletteColor(bg2.output.below.palette);
    }
    if (bg3.output.below.priority > priority) {
      priority = bg3.output.below.priority;
      math.below.color = paletteColor(bg3.output.below.palette);
    }
    if (bg4.output.below.priority > priority) {
      priority = bg4.output.below.priority;
      math.below.color = paletteColor(bg4.output.below.palette);
    }
    if (obj.output.below.priority > priority) {
      priority = obj.output.below.priority;
      math.below.color = paletteColor(obj.output.below.palette);
    }

    math.transparent = priority == 0;
    if (math.transparent) math.below.color = paletteColor(0);

    if (!hires) return 0;
    if (!math.below.colorEnable) return math.above.colorEnable ? math.below.color : 0;

    return blend(math.above.colorEnable ? math.below.color : 0,
                 math.blendMode ? math.above.color : fixedColor);
  }

  ushort above() {
    debug (PPU_SCR) printf("ppu.screen.above\n");
    if (_io.displayDisable || (!_io.overscan && vcounter >= 225)) return 0;

    uint priority;
    if (bg1.output.above.priority) {
      priority = bg1.output.above.priority;
      // if (io.directColor && (io.bgMode == 3 || bgMode == 4 || bgMode == 7)) {
        // math.above.color = directColor(bg1.output.above.palette, bg1.output.above.tile);
      // }
      // else {
        // math.above.color = paletteColor(bg1.output.above.palette);
      // }
    }
    if (bg2.output.above.priority > priority) {
      priority = bg2.output.above.priority;
      math.above.color = paletteColor(bg2.output.above.palette);
      // math.below.colorEnable = io.bg2.colorEnable;
    }
    if (bg3.output.above.priority > priority) {
      priority = bg3.output.above.priority;
      math.above.color = paletteColor(bg3.output.above.palette);
      // math.below.colorEnable = io.bg3.colorEnable;
    }
    if (bg4.output.above.priority > priority) {
      priority = bg4.output.above.priority;
      math.above.color = paletteColor(bg4.output.above.palette);
      // math.below.colorEnable = io.bg4.colorEnable;
    }
    if (obj.output.above.priority > priority) {
      priority = obj.output.above.priority;
      math.above.color = paletteColor(obj.output.above.palette);
      // math.below.colorEnable = obj.colorEnable && obj.output.above.palette >= 192;
    }
    if (priority == 0) {
      math.above.color = paletteColor(0);
      // math.below.colorEnable = io.back.colorEnable;
    }

    if (!window.output.below.colorEnable) math.below.colorEnable = false;
    math.above.colorEnable = window.output.above.colorEnable;
    if (!math.below.colorEnable) return math.above.colorEnable ? math.above.color : 0;

    if (_io.blendMode && math.transparent) {
      math.blendMode = false;
      math.colorHalve = false;
    }
    else {
      math.blendMode = _io.blendMode;
      math.colorHalve = _io.colorHalve && math.above.colorEnable;
    }

    return blend(math.above.colorEnable ? math.above.color : 0,
                 math.blendMode ? math.below.color : fixedColor);
  }

  ushort blend(uint x, uint y) {
    debug (PPU_SCR) printf("ppu.screen.blend $%08x $%08x\n", x, y);
    if (_io.colorMode) {
      auto diff = x - y + 0x8420;
      auto borrow = (diff - ((x ^ y) & 0x8420)) & 0x8420;
      if (math.colorHalve) {
        return (((diff - borrow) & (borrow - (borrow >> 5))) & 0x7bde) >> 1;
      }
      else {
        return cast(ushort) (diff - borrow) & (borrow - (borrow >> 5));
      }
    }
    else {
      if (math.colorHalve) {
        return cast(ushort) (x + y - ((x ^ y) & 0x0421)) >> 1;
      }
      else {
        auto sum = x + y;
        auto carry = (sum - ((x ^ y) & 0x0421)) & 0x8420;
        return cast(ushort) ((sum - carry) | (carry - (carry >> 5)));
      }
    }
  }

  ushort paletteColor(ubyte palette) {
    debug (PPU_SCR) printf("ppu.screen.paletteColor $%02x\n", palette);
    latch.cgramAddress = palette;
    return cgram[palette];
  }

  ushort directColor(ubyte palette, uint tile) {
    debug (PPU_SCR) printf("ppu.screen.directColor $%02x tile=$%08x\n", palette, tile);
    // palette = -------- BBGGGRRR
    // tile    = ---bgr-- --------
    // output  = 0BBb00GG Gg0RRRr0
    return ((palette << 7) & 0x6000) + ((tile >> 0) & 0x1000) +
           ((palette << 4) & 0x0380) + ((tile >> 5) & 0x0040) +
           ((palette << 2) & 0x001c) + ((tile >> 9) & 0x0002);
  }

  ushort fixedColor() {
    debug (PPU_SCR) printf("ppu.screen.fixedColor\n");
    assert(0);
    // return io.colorBlue << 10 | io.colorGreen << 5 | io.colorRed << 0;
  }

  void power() {
    debug (PPU_SCR) printf("ppu.screen.power\n");
    // randomize cgram

    // io registers
  }

  void serialize() {
    assert(0);
  }
}

// I/O Registers
// -------------------------------------------------------------------------------------------------

struct IO {
  align(1):

  // $2100 INIDISP - Screen Display Register
  union {
    ubyte inidisp;
    mixin(bitfields!(ubyte, "displayBrightness", 4,
                     ubyte, "unused1",           3,
                     bool,  "displayDisable",    1));
  }

  // $2101 OBSEL - Object Size and Character Size Register
  union {
    ubyte obsel;
    mixin(bitfields!(ubyte, "tiledataAddress", 3,
                     ubyte, "nameselect",      2,
                     ubyte, "baseSize",        3));
  }

  // $2102 OAMADDL/OAMADDH - OAM Address Registers
  Reg16 oamBaseAddress;

  // $2104 OAMDATA - OAM Data Write Register
  ubyte oamData;

  // $2105 BGMODE - BG Mode and Character Size Register
  union {
    ubyte bgmode;
    mixin(bitfields!(ubyte, "bgMode",          3,
                     bool,  "bgPriority",      1,
                     bool,  "bg1TileSize",     1,
                     bool,  "bg2TileSize",     1,
                     bool,  "bg3TileSize",     1,
                     bool,  "bg4TileSize",     1));
  }

  // $2106 MOSAIC - Mosaic Register
  union {
    ubyte mosaic;
    mixin(bitfields!(bool,  "mosaicBG1Enable", 1,
                     bool,  "mosaicBG2Enable", 1,
                     bool,  "mosaicBG3Enable", 1,
                     bool,  "mosaicBG4Enable", 1,
                     ubyte, "mosaicSize",      4));
  }

  // $2107-210a BG1SC/BG2SC/BG3SC/BG4SC - BG Tilemap Address Registers
  Background.ScreenAddress[4] bgScreenAddrs;

  // $210b-210c BG12NBA/BG34NBA - BG Character Address Registers
  Background.TileData[2] bgTileData;

  // $210d-2114 BG1HOFS/BG1VOFS/BG2HOVS/BG2VOFS/BG3HOFS/BG3VOFS/BG4HOFS/BG4VOFS - Scroll Registers
  union {
    BGOffset[4] bgOffset;
    ubyte bg1HScrollOffset;
    ubyte bg1VScrollOffset;
    ubyte bg2HScrollOffset;
    ubyte bg2VScrollOffset;
    ubyte bg3HScrollOffset;
    ubyte bg3VScrollOffset;
    ubyte bg4HScrollOffset;
    ubyte bg4VScrollOffset;

    static struct BGOffset {
      ubyte h;
      ubyte v;
    }
  }

  // $2115 VMAIN - Video Port Control Register
  union {
    ubyte vmain;
    mixin(bitfields!(ubyte, "vramIncrementSize", 2,
                     ubyte, "vramMapping",       2,
                     byte,  "unused2",            3,
                     bool,  "vramIncrementMode", 1));
  }

  // $2116-2117 VMADDL/VMADDH - VRAM Address Registers
  Reg16 vramAddress;

  // $2118-2119 VMDATAL/VMDATAH - VRAM Data Write Registers
  Reg16 vramData;

  // $211a M7SEL - Mode 7 Settings Register
  union {
    ubyte m7sel;
    mixin(bitfields!(bool,  "hflipMode7",  1,
                     bool,  "vflipMode7",  1,
                     byte,  "unused3",     4,
                     ubyte, "repeatMode7", 2));
  }

  // $211b-2120 M7A/M7B/M7C/M7D/M7X/M7Y - Mode 7 Matrix Registers
  union {
    ubyte[6] m7;
    struct {
      ubyte m7a;
      ubyte m7b;
      ubyte m7c;
      ubyte m7d;
      ubyte m7x;
      ubyte m7y;
    }
  }

  // $2121 CGADD - CGRAM Address Register
  ubyte cgramAddress;

  // $2122 CGDATA - CGRAM Data Write Register
  ubyte cgramData;

  // $2123-2125 W12SEL/W34SEL/WOBJSEL - Window Mask Settings Registers
  ubyte w12sel;
  ubyte w34sel;
  ubyte wobjsel;

  // $2126-2129 WH0/WH1/WH2/WH3 - Window Position Registers
  union {
    ubyte[4] wh;
    struct {
      ubyte wh0;
      ubyte wh1;
      ubyte wh2;
      ubyte wh3;
    }
  }

  // $212a-212b WBGLOG/WOBJLOG - Window Mask Logic Registers
  union {
    ubyte wbglog;
    mixin(bitfields!(ubyte, "bg1Mask", 2,
                     ubyte, "bg2Mask", 2,
                     ubyte, "bg3Mask", 2,
                     ubyte, "bg4Mask", 2));
  }
  union {
    ubyte wobjlog;
    mixin(bitfields!(ubyte, "objMask", 2,
                     ubyte, "colMask", 2,
                     ubyte, "unused4", 4));
  }

  // $212c-212d TM/TS - Screen Destination Registers
  union {
    ubyte tm;
    mixin(bitfields!(bool, "bg1AboveEnable", 1,
                     bool, "bg2AboveEnable", 1,
                     bool, "bg3AboveEnable", 1,
                     bool, "bg4AboveEnable", 1,
                     bool, "objAboveEnable", 1,
                     byte, "unused5",        3));
  }
  union {
    ubyte ts;
    mixin(bitfields!(bool, "bg1BelowEnable", 1,
                     bool, "bg2BelowEnable", 1,
                     bool, "bg3BelowEnable", 1,
                     bool, "bg4BelowEnable", 1,
                     bool, "objBelowEnable", 1,
                     byte, "unused6",        3));
  }

  // $212e-212f TMW/TSW - Window Mask Destination Registers
  union {
    ubyte tmw;
    mixin(bitfields!(bool, "bg1AboveEnableWindow", 1,
                     bool, "bg2AboveEnableWindow", 1,
                     bool, "bg3AboveEnableWindow", 1,
                     bool, "bg4AboveEnableWindow", 1,
                     bool, "objAboveEnableWindow", 1,
                     byte, "unused7",              3));
  }
  union {
    ubyte tsw;
    mixin(bitfields!(bool, "bg1BelowEnableWindow", 1,
                     bool, "bg2BelowEnableWindow", 1,
                     bool, "bg3BelowEnableWindow", 1,
                     bool, "bg4BelowEnableWindow", 1,
                     bool, "objBelowEnableWindow", 1,
                     byte, "unused8",              3));
  }

  // $2130-2132 CGWSEL/CGADSUB/COLDATA - Color Math Registers
  union {
    ubyte cgwsel;
    mixin(bitfields!(bool,  "directColor", 1,
                     bool,  "blendMode",   1,
                     ubyte, "unused9",    2,
                     ubyte, "belowMask",   2,
                     ubyte, "aboveMask",   2));
  }
  union {
    ubyte cgaddsub;
    mixin(bitfields!(bool, "bg1ColorEnable",  1,
                     bool, "bg2ColorEnable",  1,
                     bool, "bg3ColorEnable",  1,
                     bool, "bg4ColorEnable",  1,
                     bool, "objColorEnable",  1,
                     bool, "backColorEnable", 1,
                     bool, "colorHalve",      1,
                     bool, "colorMode",       1));
  }
  union {
    ubyte coldata;
    mixin(bitfields!(ubyte, "colData",  4,
                     bool,  "colR",     1,
                     bool,  "colG",     1,
                     bool,  "colB",     1,
                     bool,  "unused10", 1));
  }

  // $2133 SETINI - Screen Mode Select Register
  union {
    ubyte setini;
    mixin(bitfields!(bool, "interlace",    1,
                     bool, "objInterlace", 1,
                     bool, "overscan",     1,
                     bool, "pseudoHires",  1,
                     bool, "unused11",     1,
                     bool, "extbg",        1,
                     byte, "unused12",     2));
  }

  // $2134-2136 MPYL/MPYM/MPYH - Multiplication Result Registers
  ubyte mpyl;
  ubyte mpym;
  ubyte mpyh;

  // $2137 SLHV - Software Latch Register
  ubyte slhv;

  // $2138 OAMDATAREAD - OAM Data Read Register
  ubyte oamDataRead;

  // $2139-213a VMDATALREAD/VMDATAHREAD - VRAM Data Read Registers
  Reg16 vmDataRead;

  // $213b CGDATAREAD - CGRAM Data Read Register
  ubyte cgramDataRead;

  // $213c-213d OPHCT/OPVCT - Scanline Location Registers
  ubyte hcounter;
  ubyte vcounter;

  // $213e-213f STAT77/STAT88 - PPU Status Registers
  Reg16 stat;

  // $2140-2143 APUIO0/APUIO1/APUIO2/APUIO3 - APU IO Registers
  ubyte[4] apuIOPort;

  // $2144-217f
  ubyte[0x3c] unused;

  // $2180 WMDATA - WRAM Data Register
  ubyte wmData;

  // $2181-2183
  Reg16 wramAddress;
}

// static assert(IO.sizeof == 0x84);

// I/O
// -------------------------------------------------------------------------------------------------

nothrow @nogc:

bool accessVRAM() {
  return !_io.displayDisable && vcounter < vdisp;
}

ushort addressVRAM() {
  auto address = _io.vramAddress;
  switch (_io.vramMapping) {
  default: assert(0);
  case 0: return address;
  // case 1: return
  }
}

ushort readVRAM() {
  debug (PPU_MEM) printf("ppu.readVRAM\n");
  if (accessVRAM) return 0x0000;
  return vram[addressVRAM];
}

void writeVRAM(bool isByte, ubyte data) {
  debug (PPU_MEM) printf("ppu.writeVRAM isByte=%b data=$%02x\n", isByte, data);
  if (accessVRAM) return;
  vram[addressVRAM + isByte] = data;
}

alias accessOAM = accessVRAM;

ubyte readOAM(ushort addr) {
  debug (PPU_MEM) printf("ppu.readOAM $%04x\n", addr);
  if (accessOAM) addr = latch.oamAddress;
  return obj.oam.read(addr);
}

void writeOAM(ushort addr, ubyte data) {
  debug (PPU_MEM) printf("ppu.writeOAM $%04x $%02x\n", addr, data);
  if (accessOAM) addr = latch.oamAddress;
  obj.oam.write(addr, data);
}

bool accessCGRAM() {
  return accessOAM && hcounter > 87 && hcounter < 1096;
}

ubyte readCGRAM(bool n, ubyte addr) {
  debug (PPU_MEM) printf("ppu.readCGRAM $%02x n=%b\n", addr, n);
  if (accessCGRAM) addr = latch.cgramAddress;
  return cast(ubyte) (screen.cgram[addr] >> (8 * n));
}

void writeCGRAM(ubyte addr, ushort data) {
  debug (PPU_MEM) printf("ppu.writeCGRAM $%02x $%04x\n", addr, data);
  if (accessCGRAM) addr = latch.cgramAddress;
  screen.cgram[addr] = data;
}

ubyte readIO(ushort addr, ubyte data) {
  debug (IO) printf("ppu.readIO  $%06x [d=$%02x]\n", addr, data);
  cpu.processor.synchronize(processor);

  switch (addr) {
  default:
    debug printf("PPU read from unknown I/O address: $%04x\n", addr);
    return data;

  case 0x2104:..
  case 0x212a:
    return ppu1.mdr;

  case 0x2134:
    auto result = _io.m7a * cast(ubyte) (_io.m7b >> 8);
    // return ppu1.mdr = result 
    assert(0);

  case 0x2140:..
  case 0x2143:
    cpu.processor.synchronize(smp.processor);
    return smp.readPort(cast(ubyte) addr.bits!2);
  }
}

void writeIO(ushort addr, ubyte data) {
  debug (PPU_IO) printf("ppu.writeIO $%06x [d=$%02x]\n", addr, data);
  cpu.processor.synchronize(processor);

  switch (addr) {
  default:
    debug printf("PPU write to unknown I/O address: $%04x = $%02x\n", addr, data);
    return;

  case 0x2100: // INIDISP
    if (_io.displayDisable && vcounter == vdisp) obj.addressReset();
    _io.inidisp = data;
    return;

  case 0x2101: // OBSEL
    _io.obsel = data;
    return;

  case 0x2102: // OAMADDL
    _io.oamBaseAddress = (_io.oamBaseAddress & 0x200) | (data << 1);
    obj.addressReset();
    return;

  case 0x2103: // OAMADDH
    _io.oamBaseAddress = (data & 0x1) << 9 | (_io.oamBaseAddress & 0x01fe);
    obj.addressReset();
    return;

  case 0x2104: // OAMDATA
    // auto latchBit = io.oamAddress & 1;
    // auto address  = io.oamAddress++;

    // if (latchBit == 0) latch.oam = data;
    // if (address & (1 << 9)) {
    //   writeOAM(address, data);
    // }
    // else {
    //   writeOAM((address & ~1) + 0, latch.oam);
    //   writeOAM((address & ~1) + 1, data);
    // }
    // obj.setFirstSprite();
    // return;
    assert(0);

  case 0x2105: // BGMODE
    _io.bgmode = data;
    updateVideoMode();
    return;

  case 0x2106: // MOSAIC
    _io.mosaic = data;
    return;

  case 0x2107:.. // BG1SC .. BG34NBA
  case 0x210c:
    auto p = cast(ubyte*) &io;
    p[addr - 0x2100] = data;
    return;

  case 0x210d:
    assert(0);
    // io.hoffsetMode7 = data << 8 | latch.mode7;
    // latch.mode7 = data;

    // bg1.io.hoffset = data << 8 | (latch.bgofs & ~7) | (bg1.io.hoffset >> 8 & 7);
    // latch.bgofs = data;
    // return;

  case 0x210e: // BG1VOFS
    // io.voffsetMode7 = data << 8 | latch.mode7;
    // latch.mode7 = data;

    // bg1.io.voffset = data << 8 | latch.bgofs;
    // latch.bgofs = data;
    // return;
    assert(0);

  case 0x210f: // BG2HOFS
    bg2.io.hoffset = data << 8 | (latch.bgofs & ~7) | (bg2.io.hoffset >> 8 & 7);
    latch.bgofs = data;
    return;

  case 0x2110: // BG2VOFS
    bg2.io.voffset = data << 8 | latch.bgofs;
    latch.bgofs = data;
    return;

  case 0x2111: // BG3HOFS
    bg3.io.hoffset = data << 8 | (latch.bgofs & ~7) | (bg3.io.hoffset >> 8 & 7);
    latch.bgofs = data;
    return;

  case 0x2112: // BG3VOFS
    bg3.io.voffset = data << 8 | latch.bgofs;
    latch.bgofs = data;
    return;

  case 0x2113: // BG4HOFS
    bg4.io.hoffset = data << 8 | (latch.bgofs & ~7) | (bg4.io.hoffset >> 8 & 7);
    latch.bgofs = data;
    return;

  case 0x2114: // BG4VOFS
    bg4.io.voffset = data << 8 | latch.bgofs;
    latch.bgofs = data;
    return;

  case 0x2115: // VMAIN
    _io.vmain = data;
    return;

  case 0x2116: // VMADDL
    _io.vramAddress.l = data;
    latch.vram = readVRAM();
    return;

  case 0x2117: // VMADDH
    _io.vramAddress.h = data;
    latch.vram = readVRAM();
    return;

  case 0x2118: // VMDATAL
    writeVRAM(0, data);
    if (!_io.vramIncrementMode) _io.vramAddress += vramIncrementSize[_io.vramIncrementSize];
    return;

  case 0x2119: // VMDATAH
    writeVRAM(1, data);
    if (!_io.vramIncrementMode) _io.vramAddress += vramIncrementSize[_io.vramIncrementSize];
    return;

  case 0x211a: // M7SEL
    _io.m7sel = data;
    return;

  case 0x211b:.. // M7A .. M7Y
  case 0x2120:
    // TODO:
    return;

  case 0x2121: // CGADD
    _io.cgramAddress = data;
    latch.cgramAddressUse = 0;
    return;

  case 0x2122: // CGDATA
    if ((latch.cgramAddressUse = !latch.cgramAddressUse) == 0) {
      latch.cgram = data;
    }
    else {
      writeCGRAM(_io.cgramAddress++, (data & 0b00111111) << 8 | latch.cgram);
    }
    return;

  case 0x2123:..
  case 0x2132:
    auto p = cast(ubyte*) &io;
    p[addr - 0x2100] = data;
    return;

  case 0x2133: // SETINI
    _io.setini = data;
    updateVideoMode();
    return;

  case 0x2140:..
  case 0x2141:
    cpu.processor.synchronize(smp.processor);
    smp.writePort(addr & 2, data);
    return;

  case 2180: // WMDATA
  case 2181: // wram addr
  case 2182:
  case 2183:
    assert(0);
  }
}

void latchCounters() {
  cpu.processor.synchronize(processor);
  _io.hcounter = cast(ubyte) hdot;
  _io.vcounter = cast(ubyte) vcounter;
  latch.counters = 1;
}

void updateVideoMode() {
  switch (_io.bgMode) {
  default: assert(0);
case 0:
    bg1.io.mode = Background.Mode.bpp2;
    bg2.io.mode = Background.Mode.bpp2;
    bg3.io.mode = Background.Mode.bpp2;
    bg4.io.mode = Background.Mode.bpp2;
    // memory.assign(bg1.io.priority, 8, 11);
    // memory.assign(bg2.io.priority, 7, 10);
    // memory.assign(bg3.io.priority, 2,  5);
    // memory.assign(bg4.io.priority, 1,  4);
    // memory.assign(obj.io.priority, 3,  6, 9, 12);
    break;

  case 1:
    bg1.io.mode = Background.Mode.bpp4;
    bg2.io.mode = Background.Mode.bpp4;
    bg3.io.mode = Background.Mode.bpp2;
    bg4.io.mode = Background.Mode.inactive;
    if(_io.bgPriority) {
      // memory.assign(bg1.io.priority, 5,  8);
      // memory.assign(bg2.io.priority, 4,  7);
      // memory.assign(bg3.io.priority, 1, 10);
      // memory.assign(obj.io.priority, 2,  3, 6, 9);
    } else {
      // memory.assign(bg1.io.priority, 6,  9);
      // memory.assign(bg2.io.priority, 5,  8);
      // memory.assign(bg3.io.priority, 1,  3);
      // memory.assign(obj.io.priority, 2,  4, 7, 10);
    }
    break;

  case 2:
    bg1.io.mode = Background.Mode.bpp4;
    bg2.io.mode = Background.Mode.bpp4;
    bg3.io.mode = Background.Mode.inactive;
    bg4.io.mode = Background.Mode.inactive;
    // memory.assign(bg1.io.priority, 3, 7);
    // memory.assign(bg2.io.priority, 1, 5);
    // memory.assign(obj.io.priority, 2, 4, 6, 8);
    break;

  case 3:
    bg1.io.mode = Background.Mode.bpp8;
    bg2.io.mode = Background.Mode.bpp4;
    bg3.io.mode = Background.Mode.inactive;
    bg4.io.mode = Background.Mode.inactive;
    // memory.assign(bg1.io.priority, 3, 7);
    // memory.assign(bg2.io.priority, 1, 5);
    // memory.assign(obj.io.priority, 2, 4, 6, 8);
    break;

  case 4:
    bg1.io.mode = Background.Mode.bpp8;
    bg2.io.mode = Background.Mode.bpp2;
    bg3.io.mode = Background.Mode.inactive;
    bg4.io.mode = Background.Mode.inactive;
    // memory.assign(bg1.io.priority, 3, 7);
    // memory.assign(bg2.io.priority, 1, 5);
    // memory.assign(obj.io.priority, 2, 4, 6, 8);
    break;

  case 5:
    bg1.io.mode = Background.Mode.bpp4;
    bg2.io.mode = Background.Mode.bpp2;
    bg3.io.mode = Background.Mode.inactive;
    bg4.io.mode = Background.Mode.inactive;
    // memory.assign(bg1.io.priority, 3, 7);
    // memory.assign(bg2.io.priority, 1, 5);
    // memory.assign(obj.io.priority, 2, 4, 6, 8);
    break;

  case 6:
    bg1.io.mode = Background.Mode.bpp4;
    bg2.io.mode = Background.Mode.inactive;
    bg3.io.mode = Background.Mode.inactive;
    bg4.io.mode = Background.Mode.inactive;
    // memory.assign(bg1.io.priority, 2, 5);
    // memory.assign(obj.io.priority, 1, 3, 4, 6);
    break;

  case 7:
    if(!_io.extbg) {
      bg1.io.mode = Background.Mode.mode7;
      bg2.io.mode = Background.Mode.inactive;
      bg3.io.mode = Background.Mode.inactive;
      bg4.io.mode = Background.Mode.inactive;
      // memory.assign(bg1.io.priority, 2);
      // memory.assign(obj.io.priority, 1, 3, 4, 5);
    } else {
      bg1.io.mode = Background.Mode.mode7;
      bg2.io.mode = Background.Mode.mode7;
      bg3.io.mode = Background.Mode.inactive;
      bg4.io.mode = Background.Mode.inactive;
      // memory.assign(bg1.io.priority, 3);
      // memory.assign(bg2.io.priority, 1, 5);
      // memory.assign(obj.io.priority, 2, 4, 6, 7);
    }
    break;
  }
  assert(0);
}

immutable vramIncrementSize = [1, 32, 128, 128];
