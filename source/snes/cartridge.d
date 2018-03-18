module snes.cartridge;

import std.bitmanip : bitfields;
import std.conv : to;
import std.exception;
import std.math;
import std.stdio;
import std.string : indexOf, lastIndexOf;

import console = emulator.console;

import mem = snes.memory;

debug {
  import core.stdc.stdio;

  debug = Pak;
}

// Core
// -------------------------------------------------------------------------------------------------

private __gshared {
  uint base;
  Type type;
  DSP1Type dsp1Type;
  Features features;
}

enum Region { NTSC, PAL }

enum Type {
  Unknown,
  LoROM,
  HiROM,
  ExLoROM,
  ExHiROM,
  SuperFX,
  SA1,
  GameBoy,
  Satellaview,
  SufamiTurbo,
  SuperGameBoy1,
  SuperGameBoy2
}

enum DSP1Type {
  None,
  LoROM1MB,
  LoROM2MB,
  HiROM
}

union Features {
  uint _; alias _ this;
  mixin(bitfields!(bool, "hasBSXSlot",    1,
                   bool, "hasSuperFX",    1,
                   bool, "hasSA1",        1,
                   bool, "hasSharpRTC",   1,
                   bool, "hasEpsonRTC",   1,
                   bool, "hasSDD1",       1,
                   bool, "hasSPC7110",    1,
                   bool, "hasCX4",        1,
                   bool, "hasDSP1",       1,
                   bool, "hasDSP2",       1,
                   bool, "hasDSP3",       1,
                   bool, "hasDSP4",       1,
                   bool, "hasOBC1",       1,
                   bool, "hasST010",      1,
                   bool, "hasST011",      1,
                   bool, "hasST018",      1,
                   bool, "checksumMatch", 1,
                   uint, "unused", 15));
}

nothrow {
  string title() { assert(0); }
  Region region() { assert(0); }
  Type memoryMapType() { return type; }
  Features feats() { return features; }
}

const(ROMSpecifications)* romSpecifications() {
  return cast(ROMSpecifications*) &mem.rom[base];
}

void load(string path) {
  console.info("Load ", path);

  auto file = File(path, "r");
  auto size = file.size.to!uint;

  // Skip the SMC header.
  if ((size & 0x7fff) == 0x200) {
    console.trace("Skipping SMC header.");
    file.seek(0x200);
    size -= 0x200;
  }

  // Read the entire file directly at its final place.
  enforce(size >= 0x8000,          "File too small.");
  enforce(size < mem.MAX_ROM_SIZE, "File too big.");
  file.rawRead(mem.rom[0..size]);

  readHeader(size);

  if (features.hasCX4) {
    assert(0);
  }
  else if (features.hasSPC7110) {
    assert(0);
  }
  else if (features.hasSDD1) {
    assert(0);
  }
  else {
    final switch (type) with (Type) {
    case Unknown:
    case GameBoy: return;

    case Satellaview:
    // case LoROMSatellaview:
      break;

    case SufamiTurbo:
      break;

    case SuperGameBoy1:
    case SuperGameBoy2:
      break;

    case LoROM:   mem.mapLoROM(size);   break;
    case HiROM:   mem.mapHiROM(size);   break;
    case ExLoROM: mem.mapExLoROM(size); break;
    case ExHiROM: mem.mapExHiROM(size); break;
    case SuperFX: mem.mapSuperFX(size); break;
    case SA1:     mem.mapSA1(size);     break;
    }
  }

  // Detect appended firmware.
  // TODO
}

enum HeaderAddr {
  lo = 0x007fc0,
  hi = 0x00ffc0,
  ex = 0x40ffc0
}

void readHeader(uint size) {
  scope (success) {
    console.trace("Type: ", type);
    console.trace("has BSX slot ", features.hasBSXSlot);
    console.trace("has Super FX ", features.hasSuperFX);
    console.trace("has SA1 ", features.hasSA1);
    console.trace("has Sharp RTC ", features.hasSharpRTC);
    console.trace("has Epson RTC ", features.hasEpsonRTC);
    console.trace("has S-DD1 ", features.hasSDD1);
    console.trace("has SPC7110 ", features.hasSPC7110);
    console.trace("has Cx4 ", features.hasCX4);
    console.trace("has DSP1 ", features.hasDSP1);
    console.trace("has DSP2 ", features.hasDSP2);
    console.trace("has DSP3 ", features.hasDSP3);
    console.trace("has DSP4 ", features.hasDSP4);
    console.trace("has OBC-1 ", features.hasOBC1);
    console.trace("has ST010 ", features.hasST010);
    console.trace("has ST011 ", features.hasST011);
    console.trace("has ST018 ", features.hasST018);
  }

  features = 0;

  // Detect Game Boy carts
  if (size >= 0x0140 &&
      mem.rom[0x0104] == 0xce && mem.rom[0x0105] == 0xed && mem.rom[0x0106] == 0x66 && mem.rom[0x0107] == 0x66 &&
      mem.rom[0x0108] == 0xcc && mem.rom[0x0109] == 0x0d && mem.rom[0x010a] == 0x00 && mem.rom[0x010b] == 0x0b)
  {
    type = Type.GameBoy;
    return;
  }

  base = findHeader(size);
  auto spec = romSpecifications;

  auto ramSize = 1024 << (spec.ramSize & 7);
  auto romSize = size;
  if (ramSize == 1024) ramSize = 0; // No RAM present.

  // 0, 1, 13 = NTSC, 2-12 = PAL
  auto region = spec.region <= 1 || spec.region >= 13 ? Region.NTSC : Region.PAL;
  console.trace("Region: ", region);

  // Detect BS-X flash carts
  // TODO

  // Detect Sufami Turbo carts
  // TODO

  // Detect Super Game Boy BIOS
  if (spec.name[0..14] == "Super GAMEBOY2") {
    type = Type.SuperGameBoy2;
    return;
  }

  if (spec.name[0..13] == "Super GAMEBOY") {
    type = Type.SuperGameBoy1;
    return;
  }

  // Detect competition carts
  // TODO:

  // Detect presence of BS-X flash cartridge connector (reads extended header information)
  // TODO:

  if (features.hasBSXSlot) {
    assert(0);
  }
  else {
    // Standard cart
    switch (base) {
    case 0x00_7fc0: type = spec.mapMode == 0x32 || size >= 0x40_1000 ? Type.ExLoROM : Type.LoROM; break;
    case 0x00_ffc0: type = Type.HiROM;   break;
    case 0x40_ffc0: type = Type.ExHiROM; break;
    default:        type = Type.Unknown; return;
    }
  }

  switch (spec.mapMode) {
  case 0x20:
    switch (spec.romType) {
    case 0x13:
    case 0x14:
    case 0x15:
    case 0x1a:
      features.hasSuperFX = true;
      type = Type.SuperFX;
      ramSize = 1024 << (mem.rom[base - 3] & 7);
      if (ramSize == 1024) ramSize = 0;
      break;

    case 0x03: features.hasDSP1 = true; break;
    case 0x05: features.hasDSP2 = true; break;
    case 0xf3: features.hasCX4  = true; break;
    default:
    }
    break;

  case 0x21:
    features.hasDSP1 = spec.romType == 0x03;
    break;

  case 0x23:
    switch (spec.romType) {
    case 0x32:
    case 0x34:
    case 0x35:
      features.hasSA1 = true;
      type = Type.SA1;
      break;

    default:
    }
    break;

  case 0x30:
    switch (spec.romType) {
    case 0x03: features.hasDSP4 = true; break;
    case 0x05:
      features.hasDSP3 = spec.region == 0xb2;
      features.hasDSP1 = !features.hasDSP3;
      break;
    case 0x25:
    case 0xf5: features.hasST018 = true; break;
    case 0xf6:
      features.hasST010 = romSize >= 10;
      features.hasST011 = !features.hasST010;
      break;
    default:
    }
    break;

  case 0x31: features.hasDSP1 = spec.romType == 0x03 || spec.romType == 0x05; break;
  case 0x32: features.hasSDD1 = spec.romType == 0x43 || spec.romType == 0x45; break;
  case 0x35: features.hasSharpRTC = spec.romType == 0x55; break;

  case 0x3a:
    features.hasEpsonRTC = spec.romType == 0xf9;
    features.hasSPC7110 = features.hasEpsonRTC || spec.romType == 0xf5;
    break;

  default:
  }

  if (features.hasDSP1) {
    switch (spec.mapMode & 0x2f) {
    case 0x20: dsp1Type = size <= 0x10_000 ? DSP1Type.LoROM1MB : DSP1Type.LoROM2MB; break;
    case 0x21: dsp1Type = DSP1Type.HiROM; break;
    default:
    }
  }
}

HeaderAddr findHeader(uint size) {
  auto lo = headerScore(size, HeaderAddr.lo);
  auto hi = headerScore(size, HeaderAddr.hi);
  auto ex = headerScore(size, HeaderAddr.ex);

  if (lo >= hi && lo >= ex) {
    return HeaderAddr.lo;
  }

  if (hi >= ex) {
    return HeaderAddr.hi;
  }

  return HeaderAddr.ex;
}

int headerScore(uint size, uint addr) {
  if (size < addr + 64) {
    return 0;
  }

  auto specs = cast(ROMSpecifications*) &mem.rom[addr];

  return ~specs.complement == specs.checksum;
}

struct VectorROMMap {
  uint unused;
  ushort coprocessorEmpowerment;
  ushort programBreak;
  ushort abort;
  ushort nonMaskableInterrupt;
  ushort reset;
  ushort interruptRequest;
}

struct ROMRegistrationData {
  ushort   makerCode;
  uint     gameCode;
  ubyte[7] fixedValue;
  ubyte    expansionRAMSize;
  ubyte    specialVersion;
  ubyte    cartridgeType;
}

struct ROMSpecifications {
  immutable(char)[0x15] internalName;
  ubyte  mapMode;
  ubyte  romType;
  ubyte  romSize;
  ubyte  ramSize;
  ubyte  region;
  ubyte  company;
  ubyte  versionNumber;
  ushort complement;
  ushort checksum;

  string name() const @safe @nogc {
    auto z = internalName.indexOf('\x00');
    auto n = z == -1 ? internalName : internalName[0..z];
    auto l = internalName.lastIndexOf(' ');
    return n[0 .. l == -1 ? internalName.length : l];
  }
}
