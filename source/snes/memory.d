/**
 * References:
 *   https://en.wikibooks.org/wiki/Super_NES_Programming/SNES_memory_map
 */
module snes.memory;

import std.bitmanip : BitArray;

import cpu = snes.cpu;
import ppu = snes.ppu;

debug {
  import core.stdc.stdio : printf;

  debug = MemoryBus;
  // debug = MemoryMap;
  // debug = MemoryMapDetail;
}

enum PAGE_SIZE = 0x1000;
enum NUM_PAGES = 0x1000;
enum NUM_BANKS = 0x0100;

enum PAGES_PER_BANK = NUM_PAGES / NUM_BANKS;

enum ADDR_PAGE_SHIFT = 12;
enum BANK_PAGE_SHIFT = 4;

enum ADDR_MASK = 0xff_ffff;
enum PAGE_MASK = 0x0fff;
enum MMIO_MASK = 0xffff;

enum MAX_ROM_SIZE = 0x800_000;

private __gshared {
  // Memory Map
  Page[NUM_PAGES] pages;

  ReadFn [0x100] ioReads;
  WriteFn[0x100] ioWrites;

  BitArray ioMap;
}

package __gshared {
  // Memory
  ubyte[0x800 * PAGE_SIZE] rom;

  ubyte[0x20_000] wram;
  ubyte[0x20_000] sram;
  ubyte[0x10_000] vram;
}

package void initialize() {
  ioMap.length = NUM_PAGES;
}

package void terminate() {
  ioMap.length = 0;
}

pragma(inline, true) nothrow @nogc:

union Page {
  ubyte* memory;
  ubyte io;
}

alias ReadFn  = ubyte function(ushort addr, ubyte data);
alias WriteFn = void  function(ushort addr, ubyte data);

// enum Type {
//   WRam,
//   SRam,
//   VRam,
//   Rom
// }

// ubyte[] get(Type type) {
//   final switch (type) with (Type) {
//     case WRam: return wram;
//     case SRam: return sram;
//     case VRam: return vram;
//     case Rom:  return rom;
//   }
// }

// Utilities
// -------------------------------------------------------------------------------------------------

ushort addr(ushort page) {
  assert(page < NUM_PAGES);
  assert(page * PAGE_SIZE <= ushort.max);
  return cast(ushort) (page << ADDR_PAGE_SHIFT);
}

auto page(uint addr) {
  assert((addr & ADDR_MASK) == addr);
  return addr >> ADDR_PAGE_SHIFT;
}

auto page(ubyte bank, ushort addr) {
  return (bank << BANK_PAGE_SHIFT) | (addr >> ADDR_PAGE_SHIFT);
}

// Memory Bus
// -------------------------------------------------------------------------------------------------

private void check(uint addr, uint id, bool io) {
  debug if (cast(size_t) pages[id].memory <= ubyte.max && !io) {
    printf("Unmapped page access: $%02x:%04x\n", addr >> 16, addr & 0xffff);
    assert(0);
  }
}

ubyte read(uint addr, ubyte data = 0) {
  auto id = addr.page;
  auto io = ioMap[id];
  addr.check(id, io);

  ubyte result;
  if (io) result = ioReads[pages[id].io](addr & MMIO_MASK, data);
  else result = pages[id].memory[addr];

  debug (MemoryBus) printf("mem.read  $%06x [data=$%02x, io=%x] = $%02x\n", addr, data, io, result);
  return result;
}

void write(uint addr, ubyte data) {
  auto id = addr.page;
  auto io = ioMap[id];
  debug (MemoryBus) printf("mem.write $%06x [data=$%02x, io=%x]\n", addr, data, io);
  addr.check(id, io);

  if (io) ioWrites[pages[id].io](addr & MMIO_MASK, data);
  else pages[id].memory[addr] = data;
}

// Memory Map
// -------------------------------------------------------------------------------------------------

package:

void mapLoROM(uint size) {
  mapSystem();

  mapLoROM(0x00, 0x3f, 0x8, 0xf, size);
  mapLoROM(0x40, 0x7f, 0x0, 0xf, size);
  mapLoROM(0x80, 0xbf, 0x8, 0xf, size);
  mapLoROM(0xc0, 0xff, 0x0, 0xf, size);

  // mapDSP();
  // mapC4();
  // mapOBC1();
  // mapSETA();

  mapLoSRAM();
  mapWRAM();
}

void mapHiROM(uint size) {
  mapSystem();

  mapHiROM(0x00, 0x3f, 0x8, 0xf, size);
  mapHiROM(0x40, 0x7f, 0x0, 0xf, size);
  mapHiROM(0x80, 0xbf, 0x8, 0xf, size);
  mapHiROM(0xc0, 0xff, 0x0, 0xf, size);

  // mapDSP();

  mapHiSRAM();
  mapWRAM();
}

void mapExLoROM(uint size) {
  
}

void mapExHiROM(uint size) {
  
}

void mapSuperFX(uint size) {
  
}

void mapSA1(uint size) {
  
}

private:

void mapSystem() {
  map(0x00, 0x3f, 0x0, 0x1, wram.ptr, true);
  map(0x00, 0x3f, 0x2, 0x3, &ppu.readIO, &ppu.writeIO);
  map(0x00, 0x3f, 0x4, 0x5, &cpu.readIO, &cpu.writeIO);
  map(0x80, 0xbf, 0x0, 0x1, wram.ptr, true);
  map(0x80, 0xbf, 0x2, 0x3, &ppu.readIO, &ppu.writeIO);
  map(0x80, 0xbf, 0x4, 0x5, &cpu.readIO, &cpu.writeIO);
}

void mapWRAM() {
  map(0x7e, 0x7e, 0x0, 0xf, wram.ptr, true);
  map(0x7f, 0x7f, 0x0, 0xf, wram.ptr + 0x10_000, true);
}

void mapLoSRAM() {
  map(0x70, 0x7e, 0x0, 0xf, sram.ptr, true);
  map(0xf0, 0xff, 0x0, 0xf, sram.ptr, true);
}

void mapHiSRAM() {
  map(0x20, 0x3f, 0x6, 0x7, sram.ptr, true);
  map(0xa0, 0xbf, 0x6, 0x7, sram.ptr, true);
}

void mapC4() {
  // map(0x00, 0x3f, 0x6, 0x7); // C4
  // map(0x80, 0xbf, 0x6, 0x7); // C4
}

void mapOBC1() {
  // map(0x00, 0x3f, 0x6, 0x7); // OBC
  // map(0x80, 0xbf, 0x6, 0x7); // OBC
}

void map(ubyte bankStart, ubyte bankEnd, ushort pageStart, ushort pageEnd,
         ubyte* data, bool writable)
{
  debug (MemoryMap) printf("map $%02x-%02x:%x000-%xfff\n", bankStart, bankEnd, pageStart, pageEnd);
  foreach (ubyte b; bankStart .. bankEnd + 1) {
    foreach (ushort p; pageStart .. pageEnd + 1) {
      auto id = b.page(p.addr);
      debug (MemoryMapDetail) printf("map   $%02x-$%02x:$%x000-$%xfff [b=$%02x, p=$%04x, val=#%08x, w=%x]\n",
                                     bankStart, bankEnd, pageStart, pageEnd, b, p, data, writable);

      pages[id].memory = data;
      ioMap[id] = false;
    }
  }
}

void map(ubyte bankStart, ubyte bankEnd, ushort pageStart, ushort pageEnd, ReadFn r, WriteFn w) {
  debug (MemoryMap) printf("map $%02x-%02x:%x000-%xfff IO\n", bankStart, bankEnd, pageStart, pageEnd);
  auto io = -1;
  foreach (id; 0..0x100) {
    if (ioReads[id] is null) {
      assert(ioWrites[id] is null);

      io = id;
      ioReads [id] = r;
      ioWrites[id] = w;
      break;
    }
  }
  assert(io != -1, "IO map full");

  foreach (ubyte b; bankStart .. bankEnd + 1) {
    foreach (ushort p; pageStart .. pageEnd + 1) {
      auto id = b.page(p.addr);
      debug (MemoryMapDetail) printf("map   $%02x-$%02x:$%x000-$%xfff [b=$%02x, p=$%04x, io]\n",
                                     bankStart, bankEnd, pageStart, pageEnd, b, p, io);

      pages[id].io = cast(ubyte) io;
      ioMap[id] = true;
    }
  }
}

void mapLoROM(ubyte bankStart, ubyte bankEnd, ushort pageStart, ushort pageEnd, uint size) {
  debug (MemoryMap) printf("map $%02x-%02x:%x000-%xfff LO size=%u\n",
                           bankStart, bankEnd, pageStart, pageEnd, size);

  foreach (ubyte b; bankStart .. bankEnd + 1) {
    foreach (ushort p; pageStart .. pageEnd + 1) {
      auto a = p.addr;
      auto id = b.page(a);
      pages[id].memory = rom.ptr + mapMirror((b & 0x7f) * 0x8000, size) - (a & 0x8000);
      ioMap[id] = false;

      debug (MemoryMapDetail) printf("mapLo $%02x-$%02x:$%x000-$%xfff [b=$%02x, p=$%04x, val=#%08x]\n",
                                     bankStart, bankEnd, pageStart, pageEnd, b, p, pages[id]);
    }
  }
}

void mapHiROM(ubyte bankStart, ubyte bankEnd, ushort pageStart, ushort pageEnd, uint size) {
  debug (MemoryMap) printf("map $%02x-%02x:%x000-%xfff HI size=%u\n",
                           bankStart, bankEnd, pageStart, pageEnd, size);

  foreach (ubyte b; bankStart .. bankEnd + 1) {
    foreach (ushort p; pageStart .. pageEnd + 1) {
      auto a = p.addr;
      auto id = b.page(a);
      pages[id].memory = rom.ptr + mapMirror(b << 16, size);
      ioMap[id] = false;

      debug (MemoryMapDetail) printf("mapHi $%02x-$%02x:$%x000-$%xfff [b=$%02x, p=$%04x, val=#%08x]\n",
                                     bankStart, bankEnd, pageStart, pageEnd, b, p, pages[id]);
    }
  }
}

uint mapMirror(uint addr, uint size) {
  if (size == 0) {
    return 0;
  }

  if (addr < size) {
    return addr;
  }

  uint mask = 1 << 31;
  while ((addr & mask) == 0) {
    mask >>= 1;
  }

  if (size <= (addr & mask)) {
    return mapMirror(addr - mask, size);
  }

  return mapMirror(addr - mask, size - mask) + mask;
}
