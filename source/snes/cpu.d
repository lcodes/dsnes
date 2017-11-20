/**
 * Central Processing Unit
 *
 * Public Helpers
 * State
 * Types
 * High-Level
 *   Thread
 *   Timing
 *   DMA
 *   Memory
 * Low-Level
 *   Core
 *   Memory Core
 *   Algorithms
 *   Read Instructions
 *   Write Instructions
 *   RMW Instructions
 *   Program Counter Instructions
 *   Misc Instructions
 *   OpCode Table
 *
 * References:
 *   https://gitlab.com/higan/higan/tree/master/higan/processor/wdc65816
 *   https://gitlab.com/higan/higan/tree/master/higan/sfc/cpu
 *   https://wiki.superfamicom.org/snes/show/Registers
 */
module snes.cpu;

import std.bitmanip : BitArray, bitfields;
import std.string   : empty, indexOf;
import std.traits   : isFunction, isSigned;

import system = emulator.system;
import thread = emulator.thread;

import emulator.util : bit;
import emulator.types;

import mem = snes.memory;
import ppu = snes.ppu;
import smp = snes.smp;

debug {
  import core.stdc.stdio : printf;

  debug = CPU;
  debug = CPU_DMA;
  debug = CPU_MEM;
  debug = CPU_OPS;
  debug = CPU_IO;
  debug = CPU_Timing;
}

// Public Getters
// --------------

// TODO: make these public directly, want R/W access anyways (for debugger)

nothrow @nogc {
  const(Registers)* registers() { return &regs; }
  const(IO)*        io()        { return &_io; }

  thread.Processor processor() { return proc; }
}

// State
// -----

private __gshared {
  Status status;
  DMAChannel[8] channels;
  IO _io;
  Registers regs;
  Pipe pipe;
  ubyte _version;
  ALU alu;
  Op* ops;

  thread.Processor   proc;
  thread.Processor[] coprocessors;
  thread.Processor[] peripherals;
}

private mixin ppu.Counter!scanline;

package void initialize() {
  ppuCounter.initialize();
  initTable();
}

package void terminate() {
  ppuCounter.terminate();
}

// Types
// -----

/**
 * Processor status.
 */
struct Status {
  uint clockCount;
  uint lineClocks;

  uint dramRefreshPosition;
  uint hdmaInitPosition;
  uint hdmaPosition;
  uint dmaCounter;
  uint dmaClocks;
  uint autoJoypadCounter;
  uint autoJoypadClock;

  mixin(bitfields!(bool, "intPending",        1,
                   bool, "irqLock",           1,
                   bool, "dramRefreshed",     1,
                   bool, "hdmaInitTriggered", 1,
                   bool, "hdmaTriggered",     1,
                   bool, "nmiValid",          1,
                   bool, "nmiLine",           1,
                   bool, "nmiTransition",     1,
                   bool, "nmiPending",        1,
                   bool, "nmiHold",           1,
                   bool, "irqValid",          1,
                   bool, "irqLine",           1,
                   bool, "irqTransition",     1,
                   bool, "irqPending",        1,
                   bool, "irqHold",           1,
                   bool, "powerPending",      1,
                   bool, "resetPending",      1,
                   bool, "dmaActive",         1,
                   bool, "dmaPending",        1,
                   bool, "hdmaPending",       1,
                   bool, "hdmaMode",          1,
                   bool, "autoJoypadActive",  1,
                   bool, "autoJoypadLatch",   1,
                   uint, "__padding",         9));

  ubyte hdmaCompleted;
  ubyte hdmaDoTransfer;
}

/**
 * Processor I/O mapped registers
 */
struct IO {
  // $4016-4017
  bool joypadStrobeLatch;

  // $4200 NMITIMEN - Interrupt Enable Register
  union {
    ubyte nmitimen;
    mixin(bitfields!(bool, "autoJoypadPoll", 1,
                     byte, "unused1",        3,
                     bool, "virqEnabled",    1,
                     bool, "hirqEnabled",    1,
                     bool, "unused2",        1,
                     bool, "nmiEnabled",     1));
  }

  // $4201 WRIO - IO Port Write Register
  ubyte wrio;

  // $4202-4203 WRMPYA/WRMPYB - Multiplicand Registers
  ubyte wrmpya;
  ubyte wrmpyb;

  // $4204-4206 WRDIVL/WRDIVH/WRDIVB - Divisor & Dividend Registers
  union {
    Reg16 wrdiva;
    struct {
      ubyte wrdivl;
      ubyte wrdivh;
    }
  }
  ubyte wrdivb;

  // $4207-420a HTIMEL/HTIMEH/VTIMEL/VTIMEH - IRQ Timer Registers
  Reg16 htime;
  Reg16 vtime;

  // $420b MDMAEN - DMA Enable Register
  ubyte mdmaen;

  // $420c HDMAEN - HDMA Enable Register
  ubyte hdmaen;

  // $420d MEMSEL - ROM Speed Register
  ubyte memsel;

  // $4214-4217 RDDIVL/RDDIVH/RDMPYL/RDMPYH - Multiplication Or Divide Result Registers
  Reg16 rddiv;
  Reg16 rdmpy;

  // $4218-421f JOY1L/JOY1H/JOY2L/JOY2H/JOY3L/JOY3H/JOY4L/JOY4H - Controller Port Data Registers
  union {
    Reg16[4] joy;
    struct {
      Reg16 joy1;
      Reg16 joy2;
      Reg16 joy3;
      Reg16 joy4;
    }
  }
}

/**
 *
 */
struct ALU {
  uint mpyctr;
  uint divctr;
  uint shift;
}

/**
 *
 */
struct DMAChannel {
  align(1):

  // $43x0 DMAPx - DMA/HDMA Control Register
  union {
    byte control;
    mixin(bitfields!(bool, "direction",       1,
                     bool, "indirect",        1,
                     bool, "unused",          1,
                     bool, "reverseTransfer", 1,
                     bool, "fixedTransfer",   1,
                     uint, "transferMode",    3));
  }

  // $43x1 BBADx - DMA/HDMA Destination Register
  ubyte targetAddress;

  // $43x2-43x4 A1TxL/A1TxH/A1Bx - DMA Source Address Registers / HDMA Table Address Registers
  ushort sourceAddress;
  ubyte sourceBank;

  // $43x5-43x7 DASxL/DASxH/DASBx - DMA Size Registers / HDMA Indirect Address Registers
  union {
    ushort transferSize;
    ushort indirectAddress;
  }
  ubyte indirectBank;

  // $43x8-43x9 A2AxL/A2AxH - HDMA Mid Frame Table Address Registers
  ushort hdmaAddress;

  // $43xa NTLRx - HDMA Line Counter Register
  ubyte lineCounter;

  // $43xb-43xf
  ubyte[5] unknown;
}

static assert(DMAChannel.sizeof == 0x10);

/**
 *
 */
struct Pipe {
  uint addr;
  ubyte data;
  bool valid;
}

/**
 * Processor Flag Register
 */
union Flags {
  ubyte _; alias _ this;

  struct {
    mixin(bitfields!(bool, "c", 1,   // Carry
                     bool, "z", 1,   // Zero
                     bool, "i", 1,   // Interrupt Disable
                     bool, "d", 1,   // Decimal
                     bool, "x", 1,   // Index Register Mode
                     bool, "m", 1,   // Accumulator Register Mode
                     bool, "v", 1,   // Overflow
                     bool, "n", 1)); // Negative
  }
}

private unittest { assert(Flags(0x01).c); }
static assert(Flags.sizeof == 1);

/**
 * Processor Registers
 */
struct Registers {
  Reg24 pc; // Program Counter

  union {
    Reg16[6] r; alias r this;
    struct {
      Reg16 a; // Accumulator
      Reg16 x; // X Index
      Reg16 y; // Y Index
      Reg16 z;
      Reg16 s; // Stack Pointer
      Reg16 d; // Direct Page
    }
  }

  Reg8  b; // Data Bank
  Flags p; // Processor Status
  Reg8 mdr; // Memory Data Register

  mixin(bitfields!(bool, "e",   1, // Emulation mode
                   bool, "irq", 1, // Interrupt request
                   bool, "wai", 1, // Wait
                   bool, "stp", 1, // Stop
                   byte, "___", 4));
}

struct OldStyleJoypadRegisters {
  // $4016-4017 JOYSER0/JOYSER1 - Old Style Joypad Registers
  ubyte joyser0;
  ubyte joyser1;
}

static assert(OldStyleJoypadRegisters.sizeof == 0x02);

/**
 * Processor operation.
 */
alias Op = void function() nothrow @nogc;

// Thread
// ------

void power() {
  debug (CPU) printf("cpu.power\n");
  _version = 1;

  proc = thread.create(&entry, system.colorburst * 6);
  coprocessors = null;
  ppuCounter.reset();

  // TODO: randomize WRAM

  regs.pc  = Reg24.init;
  regs.a   = Reg16.init;
  regs.x   = Reg16.init;
  regs.y   = Reg16.init;
  regs.s   = 0x01ff;
  regs.d   = Reg16.init;
  regs.b   = Reg8.init;
  regs.p   = 0x34;
  regs.e   = true;
  regs.mdr = Reg8.init;
  regs.wai = false;
  regs.stp = false;

  _io.mdmaen = ubyte.init;
  _io.hdmaen = ubyte.init;

  status.hdmaCompleted  = ubyte.init;
  status.hdmaDoTransfer = ubyte.init;

  foreach (ref channel; channels) {
    channel.direction       = true;
    channel.indirect        = true;
    channel.unused          = true;
    channel.reverseTransfer = true;
    channel.fixedTransfer   = true;
    channel.transferMode    = 7;

    channel.targetAddress = ubyte.max;

    channel.sourceAddress = ushort.max;
    channel.sourceBank    = ubyte.max;

    channel.transferSize = ushort.max;
    channel.indirectBank = ubyte.max;

    channel.hdmaAddress = ushort.max;
    channel.lineCounter = ubyte.max;
    channel.unknown[]   = ubyte.max;
  }

  // ppu.power();
  // io.wramAddr = Reg24.init;

  _io.joypadStrobeLatch = 0;

  _io.nmiEnabled = false;
  _io.hirqEnabled = false;
  _io.virqEnabled = false;
  _io.autoJoypadPoll = false;

  _io.wrio = ubyte.max;

  _io.wrmpya = ubyte.max;
  _io.wrmpyb = ubyte.max;

  _io.wrdiva = ushort.max;
  _io.wrdivb = ubyte.max;

  _io.memsel = 8;

  _io.rddiv = ushort.init;
  _io.rdmpy = ushort.init;

  _io.joy[] = Reg16.init;

  alu.mpyctr = 0;
  alu.divctr = 0;
  alu.shift  = 0;

  pipe.valid = false;
  pipe.addr  = ushort.init;
  pipe.data  = ubyte.init;

  status.clockCount = 0;
  status.lineClocks = lineclocks;

  status.irqLock             = false;
  status.dramRefreshPosition = _version == 1 ? 530 : 538;
  status.dramRefreshed       = false;

  status.hdmaInitPosition  = _version == 1 ? 12 + 8 - dmaCounter : 12 + dmaCounter;
  status.hdmaInitTriggered = false;

  status.hdmaPosition  = 1104;
  status.hdmaTriggered = false;

  status.nmiValid      = false;
  status.nmiLine       = false;
  status.nmiTransition = false;
  status.nmiPending    = false;
  status.nmiHold       = false;

  status.irqValid      = false;
  status.irqLine       = false;
  status.irqTransition = false;
  status.irqPending    = false;
  status.irqHold       = false;

  status.powerPending = true;
  status.resetPending = false;
  status.intPending   = true;

  status.dmaActive   = false;
  status.dmaCounter  = 0;
  status.dmaClocks   = 0;
  status.dmaPending  = false;
  status.hdmaPending = false;
  status.hdmaMode    = 0;

  status.autoJoypadActive  = false;
  status.autoJoypadLatch   = false;
  status.autoJoypadCounter = 0;
  status.autoJoypadClock   = 0;

  updateTable();
}

void entry() {
  import console= emulator.console;
  console.info("ENTRY");
  while (true) {
    thread.synchronize();
    run();
  }
}

nothrow @nogc:

void run() {
  if (regs.wai) return opWait();
  if (regs.stp) return opStop();

  if (status.intPending) {
    status.intPending = false;
    if (status.nmiPending) {
      status.nmiPending = false;
      opInterrupt!(0xfffa, 0xffea);
    }
    else if (status.irqPending) {
      status.irqPending = false;
      opInterrupt!(0xfffe, 0xffee);
    }
    else if (status.resetPending) {
      status.resetPending = false;
      step(132);
      opInterrupt!(0xfffc, 0xfffc);
    }
    else if (status.powerPending) {
      status.powerPending = false;
      step(186);
      regs.pc.l = mem.read(0xfffc, regs.mdr);
      regs.pc.h = mem.read(0xfffd, regs.mdr);
    }
  }

  thread.brk();

  auto op = fetch();
  debug (CPU_OPS) printf("cpu.run $%02x\n", op);
  ops[op]();
}

// I/O
// ---

ubyte readIO(ushort addr, ubyte data) {
  debug (CPU_IO) printf("cpu.readIO  $%06x [d=$%02x]\n", addr, data);

  switch (addr) {
  default:
    debug printf("CPU read from unknown I/O address: $%04x\n", addr);
    return data;

  case 0x4016: // JOYSER0
    // 7-2 = MDR
    // 1-0 = Joypad serial data
    // return (regs.mdr & 0xfc) | ctrlPort1.data;

  case 0x4017: // JOYSER1
    // 7-5 = MDR
    // 4-2 = Always 1 (pins connected to GND)
    // 1-0 = Joypad serial data
    // return (regs.mdr & 0xe0) | 0x1c | ctrlPort2.data;
    assert(0);

  case 0x4210: // RDNMI
    // 7   = NMI acknowledge
    // 6-4 = MDR
    // 3-0 = CPU (5a22) version
    return (regs.mdr & 0x70) | (rdnmi << 7) | (_version & 0xf);

  case 0x4211: // TIMEUP
    // 7   = IRQ acknowledge
    // 6-0 = MDR
    return (regs.mdr & 0x7f) | (timeup << 7);

  case 0x4221: // HVBJOY
    // 7   = VBLANK acknowledge
    // 6   = HBLANK acknowledge
    // 5-1 = MDR
    // 0   = JOYPAD acknowledge
    ubyte v = regs.mdr & 0x3e;
    if (status.autoJoypadActive)           v |= 0x01;
    if (hcounter <= 2 || hcounter >= 1096) v |= 0x40; // HBLANK
    if (vcounter >= ppu.vdisp)             v |= 0x80; // VBLANK
    return v;

  case 0x4213: return _io.wrio;    // RDIO
  case 0x4214: return _io.rddiv.l; // RDDIVL
  case 0x4215: return _io.rddiv.h; // RDDIVH
  case 0x4216: return _io.rdmpy.l; // RDMPYL
  case 0x4217: return _io.rdmpy.h; // RDMPYH

  case 0x4218: return _io.joy1.l; // JOY1L
  case 0x4219: return _io.joy1.h; // JOY1H
  case 0x421a: return _io.joy2.l; // JOY2L
  case 0x421b: return _io.joy2.h; // JOY2H
  case 0x421c: return _io.joy3.l; // JOY3L
  case 0x421d: return _io.joy3.h; // JOY3H
  case 0x421e: return _io.joy4.l; // JOY4L
  case 0x421f: return _io.joy4.h; // JOY4H
  }
}

void writeIO(ushort addr, ubyte data) {
  debug (CPU_IO) printf("cpu.writeIO $%06x [d=$%02x]\n", addr, data);

  switch (addr) {
  default:
    debug printf("CPU write to unknown I/O address: $%04x = $%02x\n", addr, data);
    return;

  case 0x4016:
    auto b = data & 0x1;
    // ctrlPort1.latch(b);
    // ctrlPort2.latch(b);
    // return;
    assert(0);

  case 0x4200: // NMITIMEN
    nmitimenUpdate(data);
    return;

  case 0x4201: // WRIO
    if (_io.wrio.bit!7 && !data.bit!7) ppu.latchCounters();
    _io.wrio = data;
    return;

  case 0x4202: // WRMPYA
    _io.wrmpya = data;
    return;

  case 0x4203: // WRMPYB
    _io.rdmpy = 0;
    if (alu.mpyctr || alu.divctr) return;

    _io.wrmpyb = data;
    _io.rddiv = (io.wrmpyb << 8) | io.wrmpya;

    alu.mpyctr = 8; // Perform multiplication over the next 8 cycles.
    alu.shift  = io.wrmpyb;
    return;

  case 0x4204: _io.wrdivl = data; return; // WRDIVL
  case 0x4205: _io.wrdivh = data; return; // WRDIVH

  case 0x4206: // WRDIVB
    _io.rdmpy = io.wrdiva;
    if (alu.mpyctr || alu.divctr) return;

    _io.wrdivb = data;

    alu.divctr = 16; // Perform division over the next sixteen cycles.
    alu.shift  = io.wrdivb << 16;
    return;

  // case 0x4207: io.hirqPos.
    // TODO:

  case 0x420b: // DMAEN
    _io.mdmaen = data;
    if (data) status.dmaPending = true;
    return;

  case 0x420c: // HDMAEN
    _io.hdmaen = data;
    return;

  case 0x420d: // MEMSEL
    _io.memsel = data.bit!0 ? 6 : 8;
    return;
  }
}

private pragma(inline, true):

bool intPending() { return status.intPending; }
ubyte ioPortWrite() { return _io.wrio; }
bool joylatch() { return _io.joypadStrobeLatch; }



// XXX -> where
void idle() {
  status.clockCount = 6;
  dmaEdge();
  step(6);
  aluEdge();
}

// Timing
// ------

uint dmaCounter() {
  return (status.dmaCounter + hcounter) & 7;
}

void step(uint clocks) {
  status.irqLock = false;
  auto ticks = clocks >> 1;
  while (ticks--) {
    tick();
    if (hcounter & 2) {
      pollInterrupts();
    }
  }

  debug (CPU_Step) printf("step [clocks=%u]\n", clocks);
  processor.step(clocks);
  foreach (peripheral; peripherals) processor.synchronize(peripheral);

  status.autoJoypadClock += clocks;
  if (status.autoJoypadClock >= 0x100) {
    status.autoJoypadClock -= 0x100;
    // printf("TODO: stepAutoJoypadPoll()\n");
    // stepAutoJoypadPoll();
  }

  if (!status.dramRefreshed && hcounter >= status.dramRefreshPosition) {
    status.dramRefreshed = true;
    step(40);
  }

  version (Debugger) {
    synchronizeSMP();
    synchronizePPU();
    synchronizeCoprocessors();
  }
}

// Called by ppu.tick() when Hcounter == 0
void scanline() {
  debug (CPU_Timing) printf("scanline\n");
  status.dmaCounter = (status.dmaCounter + status.lineClocks) & 7;
  status.lineClocks = lineclocks;

  // Forcefully sync S-CPU to other processors
  processor.synchronize(smp.processor);
  processor.synchronize(ppu.processor);
  foreach (coprocessor; coprocessors) processor.synchronize(coprocessor);

  if (vcounter == 0) {
    // HDMA init triggers once every frame
    status.hdmaInitPosition = (_version == 1 ? 12 + 8 - dmaCounter : 12 + dmaCounter);
    status.hdmaInitTriggered = false;

    status.autoJoypadCounter = 0;
  }

  // DRAM refresh occurs once every scanline
  if (_version == 2) {
    status.dramRefreshPosition = 530 + 8 - dmaCounter;
  }
  status.dramRefreshed = false;

  // HDMA triggers once every visible scanline
  if (vcounter < ppu.vdisp) {
    status.hdmaPosition  = 1104;
    status.hdmaTriggered = false;
  }
}

void aluEdge() {
  if (alu.mpyctr) {
    alu.mpyctr--;
    if (io.rddiv & 1) {
      _io.rdmpy += alu.shift;
    }
    _io.rddiv >>= 1;
    alu.shift <<= 1;
  }

  if (alu.divctr) {
    alu.divctr--;
    _io.rddiv <<= 1;
    alu.shift >>= 1;
    if (io.rdmpy >- alu.shift) {
      _io.rdmpy -= alu.shift;
      _io.rddiv |= 1;
    }
  }
}

void dmaEdge() {
  if (status.dmaActive) {
    if (status.hdmaPending) {
      status.hdmaPending = false;
      if (hdmaEnabledChannels != 0) {
        if (dmaEnabledChannels == 0) {
          dmaStep(8 + dmaCounter);
        }
        status.hdmaMode ? hdmaInit() : hdmaRun();
        if (dmaEnabledChannels == 0) {
          step(status.clockCount - (status.dmaClocks % status.clockCount));
          status.dmaActive = false;
        }
      }
    }

    if (status.dmaPending) {
      status.dmaPending = false;
      if (dmaEnabledChannels != 0) {
        dmaStep(8 - dmaCounter);
        dmaRun();
        step(status.clockCount - (status.dmaClocks % status.clockCount));
        status.dmaActive = false;
      }
    }
  }

  if (!status.hdmaInitTriggered && hcounter >= status.hdmaInitPosition) {
    status.hdmaInitTriggered = true;
    hdmaInitReset();
    if (hdmaEnabledChannels != 0) {
      status.hdmaPending = true;
      status.hdmaMode = 0;
    }
  }

  if (!status.hdmaTriggered && hcounter >= status.hdmaPosition) {
    status.hdmaTriggered = true;
    if (hdmaActiveChannels != 0) {
      status.hdmaPending = true;
      status.hdmaMode = 1;
    }
  }

  if (!status.dmaActive && (status.dmaPending || status.hdmaPending)) {
    status.dmaClocks = 0;
    status.dmaActive = true;
  }
}

void lastCycle() {
  if (!status.irqLock) {
    status.nmiPending = status.nmiPending || nmiTest();
    status.irqPending = status.irqPending || irqTest();
    status.intPending = status.nmiPending || status.irqPending;
  }
}

// IRQ
// ---

void pollInterrupts() {
  if (status.nmiHold) {
    status.nmiHold = false;
    if (io.nmiEnabled) status.nmiTransition = true;
  }

  auto nmiValid = vcounter(2) >= ppu.vdisp;
  if (!status.nmiValid && nmiValid) {
    status.nmiLine = true; // 0->1 edge sensitive transition.
    status.nmiHold = true; // Hold /NMI for 4 cycles.
  }
  else if (status.nmiValid && !nmiValid) {
    status.nmiLine = false; // 1->0 edge sensitive transition.
  }
  status.nmiValid = nmiValid;

  status.irqHold = false;
  if (status.irqLine && (io.virqEnabled || io.hirqEnabled)) {
    status.irqTransition = true;
  }

  auto irqValid = io.virqEnabled || io.hirqEnabled;
  if (irqValid &&
      ((io.virqEnabled && vcounter(10) != (io.vtime + 0)) ||
       (io.hirqEnabled && hcounter(10) != (io.htime + 1) * 4) ||
       (io.vtime && vcounter(6) == 0) // IRQ cannot trigger on last dot of field.
       )) irqValid = false;
  if (!status.irqValid && irqValid) {
    status.irqLine = true; // 0->1 edge sensitive transition.
    status.irqHold = true; // Hold /IRQ for 4 cycles.
  }
  status.irqValid = irqValid;
}

void nmitimenUpdate(ubyte data) {
  auto nmiEnabled  = _io.nmiEnabled;
  auto virqEnabled = _io.virqEnabled;
  auto hirqEnabled = _io.hirqEnabled;
  _io.nmitimen = data;

  // 0->1 edge sensitive transition.
  if (!nmiEnabled && _io.nmiEnabled && status.nmiLine) {
    status.nmiTransition = true;
  }

  // 0->1 edge sensitive transition.
  if (_io.virqEnabled && !_io.hirqEnabled && status.irqLine) {
    status.irqTransition = true;
  }

  if (!_io.virqEnabled && !_io.hirqEnabled) {
    status.irqLine = false;
    status.irqTransition = false;
  }

  status.irqLock = true;
}

bool rdnmi() {
  auto result = status.nmiLine;
  if (!status.nmiHold) {
    status.nmiLine = false;
  }
  return result;
}

bool timeup() {
  auto result = status.irqLine;
  if (!status.irqHold) {
    status.irqLine = false;
    status.irqTransition = false;
  }
  return result;
}

bool nmiTest() {
  if (!status.nmiTransition) return false;
  status.nmiTransition = false;
  regs.wai = false;
  return true;
}

bool irqTest() {
  if (!status.irqTransition && !regs.irq) return false;
  status.irqTransition = false;
  regs.wai = false;
  return !regs.p.i;
}

// DMA
// ---

void dmaStep(uint clocks) {
  status.dmaClocks += clocks;
  step(clocks);
}

bool dmaTransferValid(ubyte bbus, uint abus) {
  // Transfers from WRAM to WRAM are invalid; chip only has one address bus.
  return bbus != 0x80 || ((abus & 0xfe_0000) != 0x7e_0000 && (abus & 0x40_e000) != 0x00_0000);
}

bool dmaAddressValid(uint abus) {
  return // A-bus access to B-bus or S-CPU registers are invalid.
    (abus & 0x40_ff00) != 0x2100 && // $00-3f,80-bf:2100-21ff
    (abus & 0x40_fe00) != 0x4000 && // $00-3f,80-bf:4000-41ff
    (abus & 0x40_ffe0) != 0x4200 && // $00-3f,80-bf:4200-421f
    (abus & 0x40_ff80) != 0x4300;   // $00-3f,80-bf:4300-437f
}

ubyte dmaRead(uint abus) {
  return dmaAddressValid(abus) ? mem.read(abus, regs.mdr) : 0x00;
}

void dmaWrite(bool valid, uint addr = 0, ubyte data = 0) {
  // Simulate two-stage pipeline for DMA transfers.
  if (pipe.valid) {
    mem.write(pipe.addr, pipe.data);
    pipe.valid = valid;
    pipe.addr = addr;
    pipe.data = data;
  }
}

void dmaTransfer(bool direction, ubyte bbus, uint abus) {
  dmaStep(4);
  if (direction) {
    regs.mdr = dmaTransferValid(bbus, abus) ? mem.read(bbus | 0x2100, regs.mdr) : 0x00;
    dmaStep(4);
    dmaWrite(dmaAddressValid(abus), abus, regs.mdr);
  }
  else {
    regs.mdr = dmaRead(abus);
    dmaStep(4);
    dmaWrite(dmaTransferValid(bbus, abus), bbus | 0x2100, regs.mdr);
  }
}

// Address Calculation

ubyte dmaAddressB(uint n, uint channel) {
  assert(0, "TODO");
  // switch (channel[n].transferMode) {
    
  // }
}

uint dmaAddress(uint n) {
  auto addr = channels[n].sourceBank << 16 | channels[n].sourceAddress;

  assert(0, "TODO");
  // if (!channel[n].fixedTransfer) {
    // if (!channel[n].reverseTransfer) {
      // channel[n].sourceAddress++;
    // }
    // else {
      // channel[n].sourceAddress--;
    // }
  // }

  // return addr;
}

uint hdmaAddress(uint n) {
  return channels[n].sourceBank << 16 | channels[n].hdmaAddress++;
}

uint hdmaIndirectAddress(uint n) {
  return channels[n].indirectBank << 16 | channels[n].indirectAddress;
}

// Channel Status

bool dmaEnabledChannels() {
  return io.mdmaen != 0;
}

bool hdmaActive(uint n) {
  auto b = 1 << n;
  return (io.hdmaen & b) != 0 && (status.hdmaCompleted | b) != 0;
}

bool hdmaActiveAfter(uint s) {
  foreach (n; s + 1 .. 8) {
    if (hdmaActive(n)) {
      return true;
    }
  }
  return false;
}

bool hdmaEnabledChannels() {
  return io.hdmaen != 0;
}

uint hdmaActiveChannels() {
  uint count;
  foreach (n; 0..8) {
    count += hdmaActive(n);
  }
  return count;
}

// DMA Core

void dmaRun1() {
  dmaStep(8);
  dmaWrite(false);
  dmaEdge();
}

void dmaRun() {
  dmaRun1();

  foreach (n; 0..8) {
    auto b = 1 << n;
    if ((io.mdmaen & b) == 0) continue;

    uint index;
    do {
      dmaTransfer(channels[n].direction, dmaAddressB(n, index++), dmaAddress(n));
      dmaEdge();
    } while ((io.mdmaen & b) != 0 && --channels[n].transferSize);

    dmaRun1();

    _io.mdmaen &= ~b;
  }

  status.irqLock = true;
}

void hdmaUpdate(uint n) {
  dmaStep(4);
  regs.mdr = dmaRead(channels[n].sourceBank << 16 | channels[n].hdmaAddress);
  dmaStep(4);
  dmaWrite(false);

  if ((channels[n].lineCounter & 0x7f) == 0) {
    channels[n].lineCounter = regs.mdr;
    channels[n].hdmaAddress++;

    auto b = 1 << n;
    if (channels[n].lineCounter == 0) {
      status.hdmaCompleted  |= b;
      status.hdmaDoTransfer &= ~b;
    }
    else {
      status.hdmaCompleted  &= ~b;
      status.hdmaDoTransfer |= b;
    }

    if (channels[n].indirect) {
      dmaStep(4);
      regs.mdr = dmaRead(hdmaAddress(n));
      channels[n].indirectAddress = regs.mdr << 8;
      dmaStep(4);
      dmaWrite(false);

      if ((status.hdmaCompleted & b) == 0 || hdmaActiveAfter(n)) {
        dmaStep(4);
        regs.mdr = dmaRead(hdmaAddress(n));
        channels[n].indirectAddress >>= 8;
        channels[n].indirectAddress |= regs.mdr << 8;
        dmaStep(4);
        dmaWrite(false);
      }
    }
  }
}

void hdmaRun() {
  dmaStep(8);
  dmaWrite(false);

  foreach (n; 0..8) {
    if (!hdmaActive(n)) continue;

    auto b = 1 << n;
    _io.mdmaen &= ~b;

    if (status.hdmaDoTransfer & b) {
      static immutable transferLength = [1, 2, 2, 4, 4, 4, 2, 4];

      foreach (index; 0..transferLength[channels[n].transferMode]) {
        auto addr = channels[n].indirect ? hdmaIndirectAddress(n) : hdmaAddress(n);
        dmaTransfer(channels[n].direction, dmaAddressB(n, index), addr);
      }
    }
  }

  foreach (n; 0..8) {
    if (!hdmaActive(n)) continue;

    channels[n].lineCounter--;

    auto b = 1 << n;
    if (channels[n].lineCounter & 0x80) {
      status.hdmaDoTransfer |= b;
    }
    else {
      status.hdmaDoTransfer &= ~b;
    }

    hdmaUpdate(n);
  }

  status.irqLock = true;
}

void hdmaInitReset() {
  status.hdmaCompleted  = ubyte.init;
  status.hdmaDoTransfer = ubyte.init;
}

void hdmaInit() {
  dmaStep(8);
  dmaWrite(false);

  foreach (n; 0..8) {
    auto b = 1 << n;
    if ((io.hdmaen & b) == 0)  continue;

    _io.mdmaen &= ~b;
    channels[n].hdmaAddress = channels[n].sourceAddress;
    channels[n].lineCounter = 0;
    hdmaUpdate(n);
  }

  status.irqLock = true;
}

// Memory
// ------

ubyte read(uint addr) {
  status.clockCount = addr.speed;
  dmaEdge();
  step(status.clockCount - 4);
  regs.mdr = mem.read(addr);
  step(4);
  aluEdge();
  return regs.mdr;
}

void write(uint addr, ubyte data) {
  aluEdge();
  status.clockCount = addr.speed;
  dmaEdge();
  step(status.clockCount);
  regs.mdr = data;
  mem.write(addr, data);
}

uint speed(uint addr) {
  if (addr & 0x40_8000) return addr & 0x80_0000 ? io.memsel : 8;
  if (addr + 0x6000 & 0x4000) return 8;
  if (addr - 0x4000 & 0x7e00) return 6;
  return 12;
}

// Core
// ----

// void E(alias f, Args...)(Args args) {
//   if (regs.e) f(args);
// }

void N(alias f, Args...)(Args args) {
  if (!regs.e) f(args);
}

ref auto L(alias f, Args...)(Args args) {
  lastCycle();
  static if (isFunction!f) f(args);
  else return f;
}

template isCPUType(T) {
  enum isCPUType = is(T == byte) || is(T == short) || is(T == ubyte) || is(T == ushort);
}

template signBit(T) if (isCPUType!T) {
  enum signBit = T.sizeof == 1 ? 0x80 : 0x8000;
}

void flag(string p, T)(int v) if (isCPUType!T) {
  static if (p.indexOf("c") != -1) {
    regs.p.c = isSigned!T ? v >= 0 : v > T.max;
  }

  static if (p.indexOf("n") != -1) {
    regs.p.n = (v & signBit!T) != 0;
  }

  static if (p.indexOf("z") != -1) {
    regs.p.z = cast(T) v == 0;
  }
}

void idleIRQ() {
  if (intPending) {
    // Modify I/O cycle to bus read cycle, do not increment PC
    read(regs.pc.d);
  }
  else {
    idle();
  }
}

void idle(string r)() {
  static if (!r.empty) {
    idle();
  }
}

void idle2() {
  if (regs.d.l) {
    idle();
  }
}

void idle4(ushort x, ushort y) {
  if (!regs.p.x || Reg16(x).h != Reg16(y).h) {
    idle();
  }
}

void idle6(ushort addr) {
  if (regs.e && regs.pc.h != Reg16(addr).h) {
    idle();
  }
}

// Memory Core
// -----------

ubyte fetch() {
  return read(regs.pc.b << 16 | regs.pc.w++);
}

ushort fetchW() {
  Reg16 data;
  data.l = fetch();
  data.h = fetch();
  return data;
}

uint fetchD() {
  Reg24 data;
  data.w = fetchW();
  data.d = fetch();
  return data;
}

ubyte pull() {
  if (regs.e) regs.s.l++; else regs.s++;
  return read(regs.s);
}

void push(ubyte data) {
  write(regs.s, data);
  if (regs.e) regs.s.l--; else regs.s--;
}

ubyte pullN() {
  return read(++regs.s);
}

void pushN(ubyte data) {
  write(regs.s--, data);
}

ubyte readDirect(uint addr) {
  if (regs.e && !regs.d.l) {
    return read(regs.d | cast(ubyte)(addr));
  }
  else {
    return readDirectN(addr);
  }
}

void writeDirect(uint addr, ubyte data) {
  if (regs.e && !regs.d.l) {
    write(regs.d | cast(ubyte)(addr), data);
  }
  else {
    writeAddr(regs.d + addr, data);
  }
}

ubyte readDirectN(uint addr) {
  return readAddr(regs.d + addr);
}

ubyte readBank(uint addr) {
  return read((regs.b << 16) | addr);
}

void writeBank(uint addr, ubyte data) {
  write((regs.b << 16) + addr, data);
}

ubyte readStack(uint addr) {
  return readAddr(regs.s + addr);
}

void writeStack(uint addr, ubyte data) {
  writeAddr(regs.s + addr, data);
}

ubyte readAddr(uint addr) {
  return read(cast(ushort)addr);
}

void writeAddr(uint addr, ubyte data) {
  write(cast(ushort)addr, data);
}

// Algorithms
// ----------

ubyte opAdcB(ubyte data) {
  int result;

  if (!regs.p.d) {
    result = regs.a.l + data + regs.p.c;
  }
  else {
    result = (regs.a.l & 0x0f) + (data & 0x0f) + (regs.p.c << 0);
    if (result > 0x09) result += 0x06;

    regs.p.c = result > 0x0f;
    result = (regs.a.l & 0x0f) + (data & 0xf0) + (regs.p.c << 4) + (result & 0x0f);
  }

  regs.p.v = (~(regs.a.l ^ data) & (regs.a.l ^ result) & 0x80) != 0;
  if (regs.p.d && result > 0x9f) result += 0x60;

  flag!("cnz", ubyte) = result;

  return regs.a.l = cast(ubyte) result;
}

ushort opAdcW(ushort data) {
  int result;

  if (!regs.p.d) {
    result = regs.a + data + regs.p.c;
  }
  else {
    result = (regs.a & 0x000f) + (data & 0x000f) + (regs.p.c << 0);
    if (result > 0x0009) result += 0x0006;

    regs.p.c = result > 0x000f;
    result = (regs.a & 0x00f0) + (data & 0x00f0) + (regs.p.c << 4) + (result & 0x000f);
    if (result > 0x009f) result += 0x0060;

    regs.p.c = result > 0x00ff;
    result = (regs.a & 0x0f00) + (data & 0x0f00) + (regs.p.c << 8) + (result & 0x00ff);
    if (result > 0x09ff) result += 0x0600;

    regs.p.c = result > 0x0fff;
    result = (regs.a & 0xf000) + (data & 0xf000) + (regs.p.c << 12) + (result & 0x0fff);
  }

  regs.p.v = (~(regs.a ^ data) & (regs.a ^ result) & 0x8000) != 0;
  if (regs.p.d && result > 0x9fff) result += 0x6000;

  flag!("cnz", ushort) = result;

  return regs.a = cast(ushort) result;
}

ubyte opSbcB(ubyte data) {
  int result;
  data = ~data;

  if (!regs.p.d) {
    result = regs.a.l + data + regs.p.c;
  }
  else {
    result = (regs.a.l & 0x0f) + (data & 0x0f) + (regs.p.c << 0);
    if (result <= 0x0f) result -= 0x06;

    regs.p.c = result > 0x0f;
    result = (regs.a.l & 0xf0) + (data & 0xf0) + (regs.p.c << 4) + (result & 0x0f);
  }

  regs.p.v = (~(regs.a.l ^ data) & (regs.a.l ^ result) & 0x80) != 0;
  if (regs.p.d && result <= 0xff) result -= 0x60;

  flag!("cnz", ubyte) = result;

  return regs.a.l = cast(ubyte) result;
}

ushort opSbcW(ushort data) {
  int result = void;
  data ^= 0xff;

  if (!regs.p.d) {
    result = regs.a + data + regs.p.c;
  }
  else {
    result = (regs.a & 0x000f) + (data & 0x000f) + (regs.p.c << 0);
    if (result <= 0x000f) result -= 0x06;

    regs.p.c = result > 0x000f;
    result = (regs.a & 0x00f0) + (data & 0x00f0) + (regs.p.c << 4) + (result & 0x000f);
    if (result <= 0x00ff) result -= 0x0060;

    regs.p.c = result > 0x00ff;
    result = (regs.a & 0x0f00) + (data & 0x0f00) + (regs.p.c << 8) + (result & 0x00ff);
    if (result <= 0x0fff) result -= -0x0600;

    regs.p.c = result > 0x0fff;
    result = (regs.a & 0xf000) + (data & 0xf000) + (regs.p.c << 12) + (result & 0x0fff);
  }

  regs.p.v = (~(regs.a ^ data) & (regs.a ^ result) & 0x8000) != 0;
  if (regs.p.d && result <= 0xffff) result -= 0x6000;

  flag!("cnz", ushort) = result;

  return regs.a = cast(ushort) result;
}

ubyte opIncB(ubyte data) {
  data++;
  flag!("nz", ubyte) = data;
  return data;
}

ushort opIncW(ushort data) {
  data++;
  flag!("nz", ushort) = data;
  return data;
}

ubyte opDecB(ubyte data) {
  data--;
  flag!("nz", ubyte) = data;
  return data;
}

ushort opDecW(ushort data) {
  data--;
  flag!("nz", ushort) = data;
  return data;
}

ubyte opAslB(ubyte data) {
  regs.p.c = (data & 0x80) != 0;
  data <<= 1;
  flag!("nz", ubyte) = data;
  return data;
}

ushort opAslW(ushort data) {
  regs.p.c = (data & 0x8000) != 0;
  data <<= 1;
  flag!("nz", ushort) = data;
  return data;
}

ubyte opLsrB(ubyte data) {
  regs.p.c = data & 1;
  data >>= 1;
  flag!("nz", ubyte) = data;
  return data;
}

ushort opLsrW(ushort data) {
  regs.p.c = data & 1;
  data >>= 1;
  flag!("nz", ushort) = data;
  return data;
}

ubyte opRolB(ubyte data) {
  auto c = regs.p.c;
  regs.p.c = (data & 0x80) != 0;
  data = cast(ubyte) (data << 1) | c;
  flag!("nz", ubyte) = data;
  return data;
}

ushort opRolW(ushort data) {
  auto c = regs.p.c;
  regs.p.c = (data & 0x8000) != 0;
  data = cast(ushort) (data << 1) | c;
  flag!("nz", ushort) = data;
  return data;
}

ubyte opRorB(ubyte data) {
  ubyte c = regs.p.c << 7;
  regs.p.c = data & 1;
  data = (data >> 1) | c;
  flag!("nz", ubyte) = data;
  return data;
}

ushort opRorW(ushort data) {
  ushort c = regs.p.c << 15;
  regs.p.c = data & 1;
  data = (data >> 1) | c;
  flag!("nz", ushort) = data;
  return data;
}

ubyte opTrbB(ubyte data) {
  regs.p.z = (data & regs.a.l) == 0;
  data &= ~regs.a.l;
  return data;
}

ushort opTrbW(ushort data) {
  regs.p.z = (data & regs.a) == 0;
  data &= ~regs.a;
  return data;
}

ubyte opTsbB(ubyte data) {
  regs.p.z = (data & regs.a.l) == 0;
  return data | regs.a.l;
}

ushort opTsbW(ushort data) {
  regs.p.z = (data & regs.a) == 0;
  return data | regs.a;
}

void opAndB(ubyte data) {
  regs.a.l &= data;
  flag!("nz", ubyte) = regs.a.l;
}

void opAndW(ushort data) {
  regs.a &= data;
  flag!("nz", ushort) = regs.a;
}

void opOraB(ubyte data) {
  regs.a.l |= data;
  flag!("nz", ubyte) = regs.a.l;
}

void opOraW(ushort data) {
  regs.a |= data;
  flag!("nz", ushort) = regs.a;
}

void opEorB(ubyte data) {
  regs.a.l ^= data;
  flag!("nz", ubyte) = regs.a.l;
}

void opEorW(ushort data) {
  regs.a ^= data;
  flag!("nz", ushort) = regs.a;
}

void opBitB(ubyte data) {
  regs.p.n = (data & 0x80) != 0;
  regs.p.v = (data & 0x40) != 0;
  regs.p.z = (data & regs.a.l) == 0;
}

void opBitW(ushort data) {
  regs.p.n = (data & 0x8000) != 0;
  regs.p.v = (data & 0x4000) != 0;
  regs.p.z = (data & regs.a) == 0;
}

void opCmpB(string r = "a")(ubyte data) {
  flag!("cnz", ubyte) = register!r.l - data;
}

void opCmpW(string r = "a")(ushort data) {
  flag!("cnz", ushort) = register!r.w - data;
}

alias opCpxB = opCmpB!"x";
alias opCpxW = opCmpW!"x";
alias opCpyB = opCmpB!"y";
alias opCpyW = opCmpW!"y";

void opLoadB(string r)(ubyte data) {
  register!r.l = data;
  flag!("nz", ubyte) = register!r.l;
}

void opLoadW(string r)(ushort data) {
  register!r.w = data;
  flag!("nz", ushort) = register!r.w;
}

alias opLdaB = opLoadB!"a";
alias opLdaW = opLoadW!"a";
alias opLdxB = opLoadB!"x";
alias opLdxW = opLoadW!"x";
alias opLdyB = opLoadB!"y";
alias opLdyW = opLoadW!"y";

// Read Instructions
// -----------------

void opImmediateReadB(string op)() {
  Reg8 data;
L!data = fetch();
  callB!op(data);
}

void opImmediateReadW(string op)() {
  Reg16 data;
  data.l = fetch();
L!data.h = fetch();
  callW!op(data);
}

void opBankReadB(string op, string r = "")() {
  auto absolute = fetchW();

  static if (!r.empty) {
    idle4(absolute, cast(ushort) (absolute + register!r));
  }

  Reg8 data;
L!data = readBank(absolute + register!r);
  callB!op(data);
}

void opBankReadW(string op, string r = "")() {
  auto absolute = fetchW();

  static if (!r.empty) {
    idle4(absolute, cast(ushort) (absolute + register!r));
  }

  Reg16 data;
  data.l = readBank(absolute + register!r + 0);
L!data.h = readBank(absolute + register!r + 1);
  callW!op(data);
}

void opLongReadB(string op, string r = "")() {
  auto address = fetchD();
  Reg8 data;
L!data = read(address + register!r);
  callB!op(data);
}

void opLongReadW(string op, string r = "")() {
  auto address = fetchD();
  Reg16 data;
  data.l = read(address + register!r + 0);
L!data.h = read(address + register!r + 1);
  callW!op(data);
}

void opDirectReadB(string op, string r = "")() {
  auto direct = fetch();
  idle2();
  idle!r();
  Reg8 data;
L!data = readDirect(direct + register!r);
  callB!op(data);
}

void opDirectReadW(string op, string r = "")() {
  auto direct = fetch();
  idle2();
  idle!r();
  Reg16 data;
  data.l = readDirect(direct + register!r + 0);
L!data.h = readDirect(direct + register!r + 1);
  callW!op(data);
}

void opIndirectReadB(string op, string r = "")() {
  auto direct = fetch();
  idle2();

  static if (r == "x") idle();

  Reg16 absolute;
  absolute.l = readDirect(direct + register!r + 0);
  absolute.h = readDirect(direct + register!r + 1);

  static if (r == "y") idle4(absolute, cast(ushort) (absolute + register!r));

  Reg8 data;
L!data = readBank(absolute);
  callB!op(data);
}

void opIndirectReadW(string op, string r = "")() {
  auto direct = fetch();
  idle2();

  static if (r == "x") idle();

  Reg16 absolute;
  absolute.l = readDirect(direct + register!r + 0);
  absolute.h = readDirect(direct + register!r + 1);

  static if (r == "y") idle4(absolute, cast(ushort) (absolute + register!r));

  Reg16 data;
  data.l = readBank(absolute + 0);
L!data.h = readBank(absolute + 1);
  callW!op(data);
}

template opIndexedIndirectReadB(string op) {
  alias opIndexedIndirectReadB = opIndirectReadB!(op, "x");
}

template opIndexedIndirectReadW(string op) {
  alias opIndexedIndirectReadW = opIndirectReadW!(op, "x");
}

template opIndirectIndexedReadB(string op) {
  alias opIndirectIndexedReadB = opIndirectReadB!(op, "y");
}

template opIndirectIndexedReadW(string op) {
  alias opIndirectIndexedReadW = opIndirectReadW!(op, "y");
}

void opIndirectLongReadB(string op, string r = "")() {
  auto direct = fetch();
  idle2();
  Reg24 address;
  address.l = readDirectN(direct + 0);
  address.h = readDirectN(direct + 1);
  address.b = readDirectN(direct + 2);
  Reg8 data;
L!data = read(address + register!r);
  callB!op(data);
}

void opIndirectLongReadW(string op, string r = "")() {
  auto direct = fetch();
  idle2();
  Reg24 address;
  address.l = readDirectN(direct + 0);
  address.h = readDirectN(direct + 1);
  address.b = readDirectN(direct + 2);
  Reg16 data;
  data.l = read(address + register!r + 0);
L!data.h = read(address + register!r + 1);
  callW!op(data);
}

void opStackReadB(string op)() {
  auto stack = fetch();
  idle();
  Reg8 data;
L!data = readStack(stack);
  callB!op(data);
}

void opStackReadW(string op)() {
  auto stack = fetch();
  idle();
  Reg16 data;
  data.l = readStack(stack + 0);
L!data.h = readStack(stack + 1);
  callW!op(data);
}

void opIndirectStackReadB(string op)() {
  auto stack = fetch();
  idle();
  Reg16 absolute;
  absolute.l = readStack(stack + 0);
  absolute.h = readStack(stack + 1);
  idle();
  Reg8 data;
L!data = readBank(absolute + regs.y);
  callB!op(data);
}

void opIndirectStackReadW(string op)() {
  auto stack = fetch();
  idle();
  Reg16 absolute;
  absolute.l = readStack(stack + 0);
  absolute.h = readStack(stack + 1);
  idle();
  Reg16 data;
  data.l = readBank(absolute + regs.y + 0);
L!data.h = readBank(absolute + regs.y + 1);
  callW!op(data);
}

// Write Instructions
// ------------------

void opBankWriteB(string r1, string r2 = "")() {
  auto absolute = fetchW();
  idle!r2();
L!writeBank(absolute + register!r2, register!r1.l);
}

void opBankWriteW(string r1, string r2 = "")() {
  auto absolute = fetchW();
  idle!r2();
  writeBank(absolute + register!r2 + 0, register!r1.l);
L!writeBank(absolute + register!r2 + 1, register!r1.h);
}

void opLongWriteB(string r)() {
  auto address = fetchD();
L!write(address + register!r, regs.a.l);
}

void opLongWriteW(string r)() {
  auto address = fetchD();
  write(address + register!r + 0, regs.a.l);
L!write(address + register!r + 1, regs.a.h);
}

void opDirectWriteB(string r1, string r2 = "")() {
  auto direct = fetch();
  idle2();
  idle!r2();
L!writeDirect(direct + register!r2, register!r1.l);
}

void opDirectWriteW(string r1, string r2 = "")() {
  auto direct = fetch();
  idle2();
  idle!r2();
  writeDirect(direct + register!r2 + 0, register!r1.l);
L!writeDirect(direct + register!r2 + 1, register!r1.h);
}

void opIndirectWriteB(string r = "")() {
  auto direct = fetch();
  idle2();
  idle!r();
  Reg16 absolute;
  absolute.l = readDirect(direct + register!r + 0);
  absolute.h = readDirect(direct + register!r + 1);
L!writeBank(absolute, regs.a.l);
}

void opIndirectWriteW(string r = "")() {
  auto direct = fetch();
  idle2();
  idle!r();
  Reg16 absolute;
  absolute.l = readDirect(direct + register!r + 0);
  absolute.h = readDirect(direct + register!r + 1);
  writeBank(absolute + 0, regs.a.l);
L!writeBank(absolute + 1, regs.a.h);
}

alias opIndexedIndirectWriteB = opIndirectWriteB!"x";
alias opIndexedIndirectWriteW = opIndirectWriteW!"x";
alias opIndirectIndexedWriteB = opIndirectWriteB!"y";
alias opIndirectIndexedWriteW = opIndirectWriteW!"y";

void opIndirectLongWriteB(string r = "")() {
  auto direct = fetch();
  idle2();
  Reg24 address;
  address.l = readDirectN(direct + 0);
  address.h = readDirectN(direct + 1);
  address.b = readDirectN(direct + 2);
L!write(address + register!r, regs.a.l);
}

void opIndirectLongWriteW(string r = "")() {
  auto direct = fetch();
  idle2();
  Reg24 address;
  address.l = readDirectN(direct + 0);
  address.h = readDirectN(direct + 1);
  address.b = readDirectN(direct + 2);
  write(address + register!r + 0, regs.a.l);
L!write(address + register!r + 1, regs.a.h);
}

alias opIndirectLongWriteYB = opIndirectLongWriteB!"y";
alias opIndirectLongWriteYW = opIndirectLongWriteW!"y";

void opStackWriteB() {
  auto stack = fetch();
  idle();
L!writeStack(stack, regs.a.l);
}

void opStackWriteW() {
  auto stack = fetch();
  idle();
  writeStack(stack + 0, regs.a.l);
L!writeStack(stack + 1, regs.a.h);
}

void opIndirectStackWriteB() {
  auto stack = fetch();
  idle();
  Reg16 absolute;
  absolute.l = readStack(stack + 0);
  absolute.h = readStack(stack + 1);
  idle();
L!writeBank(absolute + regs.y, regs.a.l);
}

void opIndirectStackWriteW() {
  auto stack = fetch();
  idle();
  Reg16 absolute;
  absolute.l = readStack(stack + 0);
  absolute.h = readStack(stack + 1);
  idle();
  writeBank(absolute + regs.y.w + 0, regs.a.l);
L!writeBank(absolute + regs.y.w + 1, regs.a.h);
}

// Modify
// ------

void opImpliedModifyB(string op, string r)() {
L!idleIRQ();
  register!r.l = callB!op(register!r.l);
}

void opImpliedModifyW(string op, string r)() {
L!idleIRQ();
  register!r = callW!op(register!r);
}

void opBankModifyB(string op, string r = "")() {
  auto absolute = fetchW();
  idle!r();
  auto data = readBank(absolute + register!r);
  idle();
  data = callB!op(data);
L!writeBank(absolute + register!r, data);
}

void opBankModifyW(string op, string r = "")() {
  auto absolute = fetchW();
  idle!r();
  Reg16 data;
  data.l = readBank(absolute + register!r + 0);
  data.h = readBank(absolute + register!r + 1);
  idle();
  data = callW!op(data);
  writeBank(absolute + register!r + 1, data.h);
L!writeBank(absolute + register!r + 0, data.l);
}

template opBankIndexedModifyB(string op) {
  alias opBankIndexedModifyB = opBankModifyB!(op, "x");
}

template opBankIndexedModifyW(string op) {
  alias opBankIndexedModifyW = opBankModifyW!(op, "x");
}

void opDirectModifyB(string op, string r = "")() {
  auto direct = fetch();
  idle2();
  auto data = readDirect(direct + register!r);
  idle();
  data = callB!op(data);
L!writeDirect(direct + register!r, data);
}

void opDirectModifyW(string op, string r = "")() {
  auto direct = fetch();
  idle2();
  Reg16 data;
  data.l = readDirect(direct + register!r + 0);
  data.h = readDirect(direct + register!r + 1);
  idle();
  data = callW!op(data);
  writeDirect(direct + register!r + 1, data.h);
L!writeDirect(direct + register!r + 0, data.l);
}

template opDirectIndexedModifyB(string op) {
  alias opDirectIndexedModifyB = opDirectModifyB!(op, "x");
}
template opDirectIndexedModifyW(string op) {
  alias opDirectIndexedModifyW = opDirectModifyW!(op, "x");
}

// Program Counter Instructions
// ----------------------------

void opBranch(int bit, bool val)() {
  if (cast(bool) (regs.p & bit) != val) {
    L!fetch();
  }
  else {
    opBranch();
  }
}

void opBranch()() {
  auto displacement = fetch();
  auto absolute = cast(ushort) (regs.pc + cast(byte) displacement);
  idle6(absolute);
L!idle();
  regs.pc.w = absolute;
}

void opBranchLong() {
  auto displacement = cast(short) fetchW();
L!idle();
  regs.pc.w = cast(ushort) (regs.pc + displacement);
}

void opJumpShort() {
  Reg16 data;
  data.l = fetch();
L!data.w = fetch();
  regs.pc.w = data;
}

void opJumpLong() {
  Reg24 data;
  data.l = fetch();
  data.h = fetch();
L!data.b = fetch();
  regs.pc = data;
}

void opJumpIndirect() {
  auto absolute = fetchW();
  Reg16 data;
  data.l = readAddr(absolute + 0);
L!data.h = readAddr(absolute + 1);
  regs.pc.w = data;
}

void opJumpIndexedIndirect() {
  auto absolute = fetchW();
  idle();
  Reg16 data;
  data.l = read(regs.pc.b << 16 | cast(ushort) (absolute + regs.x + 0));
L!data.h = read(regs.pc.b << 16 | cast(ushort) (absolute + regs.x + 0));
  regs.pc.w = data;
}

void opJumpIndirectLong() {
  auto absolute = fetchW();
  Reg24 data;
  data.l = readAddr(absolute + 0);
  data.h = readAddr(absolute + 1);
L!data.b = readAddr(absolute + 2);
  regs.pc = data;
}

void opCallShort() {
  auto data = fetchW();
  idle();
  regs.pc.w--;
  push(regs.pc.h);
L!push(regs.pc.l);
  regs.pc.w = data;
}

void opCallLong() {
  Reg24 data;
  data.l = fetch();
  data.h = fetch();
  pushN(regs.pc.b);
  idle();
  data.b = fetch();
  regs.pc.w--;
  pushN(regs.pc.h);
L!pushN(regs.pc.l);
  regs.pc = data;

  if (regs.e) {
    regs.s.h = 0x01;
  }
}

void opCallIndexedIndirect() {
  Reg16 absolute;
  absolute.l = fetch();
  pushN(regs.pc.h);
  pushN(regs.pc.l);
  absolute.h = fetch();
  idle();
  Reg16 data;
  data.l = read(regs.pc.b << 16 | cast(ushort) (absolute + regs.x + 0));
L!data.w = read(regs.pc.b << 16 | cast(ushort) (absolute + regs.x + 1));
  regs.pc.w = data;

  if (regs.e) {
    regs.s.h = 0x01;
  }
}

void opReturnInterrupt() {
  idle();
  idle();
  regs.p = pull();

  if (regs.e) {
    regs.p |= 0x30;
  }

  if (regs.p.x) {
    regs.x.h = 0x00;
    regs.y.h = 0x00;
  }

  regs.pc.l = pull();

  if (regs.e) {
  L!regs.pc.h = pull();
  }
  else {
    regs.pc.h = pull();
  L!regs.pc.b = pull();
  }

  updateTable();
}

void opReturnShort() {
  idle();
  idle();
  Reg16 data;
  data.l = pull();
  data.h = pull();
  L!idle();
  regs.pc.w = ++data;
}

void opReturnLong() {
  idle();
  idle();
  Reg24 data;
  data.l = pullN();
  data.h = pullN();
L!data.b = pullN();
  regs.pc.b = data.b;
  regs.pc.w = bit!15(++data);

  if (regs.e) {
    regs.s.h = 0x01;
  }
}

// Misc Instructions
// -----------------

void opBitImmediateB() {
  Reg8 immediate;
L!immediate = fetch();
  regs.p.z = (immediate & regs.a.l) == 0;
}

void opBitImmediateW() {
  Reg16 immediate;
  immediate.l = fetch();
L!immediate.h = fetch();
  regs.p.z = (immediate & regs.a) == 0;
}

void opNoOperation() {
L!idleIRQ();
}

void opPrefix() {
L!fetch();
}

void opExchangeBA() {
  idle();
L!idle();
  regs.a = cast(ushort) (regs.a >> 8 | regs.a << 8);
  flag!("nz", ubyte) = regs.a.l;
}

void opBlockMove(string prop, int adjust)() {
  auto targetBank = fetch();
  auto sourceBank = fetch();
  regs.b = targetBank;
  auto data = read(sourceBank << 16 | regs.x);
  write(targetBank << 16 | regs.y, data);
  idle();
  mixin("regs.x." ~ prop) += adjust;
  mixin("regs.y." ~ prop) += adjust;
L!idle();
  if (regs.a--) regs.pc.w -= 3;
}

template opBlockMoveB(int adjust) { alias opBlockMoveB = opBlockMove!("l", adjust); }
template opBlockMoveW(int adjust) { alias opBlockMoveW = opBlockMove!("w", adjust); }

void opInterrupt(int vectorE, int vectorN)() {
  auto vector = regs.e ? vectorE : vectorN;
  fetch();
N!push(regs.pc.b);
  push(regs.pc.h);
  push(regs.pc.l);
  push(regs.p);
  regs.p.i  = true;
  regs.p.d  = false;
  regs.pc.l = read(vector + 0);
L!regs.pc.h = read(vector + 1);
  regs.pc.b = 0x00;
}

bool synchronizing() {
  return false; // TODO:
}

void opPause(string r)() {
  // mixin("alias reg = regs." ~ r);

  mixin("regs." ~ r) = true;
  while (mixin("regs." ~ r) && !synchronizing) {
    L!idle();
  }

  static if (r == "wai") idle();
}

alias opPause!"stp" opStop;
alias opPause!"wai" opWait;

void opExchangeCE() {
L!idleIRQ();

  auto c = regs.p.c; // TODO: swap(C, E)
  regs.p.c = regs.e;
  regs.e = c;

  if (regs.e) {
    regs.p  |= 0x30;
    regs.x.h = 0x00;
    regs.y.h = 0x00;
    regs.s.h = 0x01;
  }

  updateTable();
}

void opSetFlag(string flag, bool value)() {
L!idleIRQ();

  mixin("regs.p." ~ flag) = value;
}

void opPFlag(bool mode)() {
  auto data = fetch();
L!idle();

  regs.p = mode ? regs.p | data : regs.p & ~data;

  if (regs.e) {
    regs.p |= 0x30;
  }

  if (regs.p.x) {
    regs.x.h = 0x00;
    regs.y.h = 0x00;
  }

  updateTable();
}

void opTransfer(string prop, string from, string to, uint mask)() {
  enum p = to ~ "." ~ prop;
L!idleIRQ();
  register!p = mixin("regs." ~ from ~ "." ~ prop);
  regs.p.n = (register!p & mask) != 0;
  regs.p.z = register!p == 0;
}

template opTransferB(string from, string to) {
  alias opTransferB = opTransfer!("l", from, to, 0x80);
}

template opTransferW(string from, string to) {
  alias opTransferW = opTransfer!("w", from, to, 0x8000);
}

alias opTransferSXB = opTransferB!("s", "x");
alias opTransferSXW = opTransferW!("s", "x");

void opTransferCS() {
L!idleIRQ();

  regs.s = regs.a;

  if (regs.e) {
    regs.s.h = 0x01;
  }
}

void opTransferXS() {
  L!idleIRQ();

  if (regs.e) {
    regs.s.l = regs.x.l;
  }
  else {
    regs.s = regs.x;
  }
}

void opPushB(string r)() {
  idle();
  lastCycle();
  static if (r[0] == 'p' || r == "b") {
    enum reg = r;
  }
  else {
    enum reg = r ~ ".l";
  }
  push(register!reg);
}

void opPushW(string r)() {
  idle();
  push(register!(r ~ ".h"));
L!push(register!(r ~ ".l"));
}

void opPushD() {
  opPushW!"d";

  if (regs.e) {
    regs.s.h = 0x01;
  }
}

void opPullB(string r)() {
  idle();
  idle();

  lastCycle();
  register!r = pull();

  regs.p.n = (register!r & 0x80) != 0;
  regs.p.z = register!r == 0;
}

void opPullW(string r)() {
  idle();
  idle();

  static if (r == "d") {
    alias p = pullN;
  }
  else {
    alias p = pull;
  }

  register!r.l = p();
  lastCycle();
  register!r.h = p();

  regs.p.n = (register!r & 0x8000) != 0;
  regs.p.z = register!r == 0;
}

void opPullD() {
  opPullW!"d";

  if (regs.e) {
    regs.s.h = 0x01;
  }
}

void opPullP() {
  idle();
  idle();
L!regs.p = pull();

  if(regs.e) {
    regs.p |= 0x30;
  }

  if (regs.p.x) {
    regs.x.h = 0x00;
    regs.y.h = 0x00;
  }

  updateTable();
}

void opPushEffectiveAddress() {
  auto data = Reg16(fetchW());
  pushN(data.h);
L!pushN(data.l);

  if (regs.e) {
    regs.s.h = 0x01;
  }
}

void opPushEffectiveIndirectAddress() {
  auto direct = fetch();
  idle2();
  Reg16 data;
  data.l = readDirectN(direct + 0);
  data.h = readDirectN(direct + 1);
  pushN(data.h);
L!pushN(data.l);

  if (regs.e) {
    regs.s.h = 0x01;
  }
}

void opPushEffectiveRelativeAddress() {
  auto displacement = fetchW();
  idle();
  auto data = Reg16(cast(ushort) (regs.pc + displacement));
  pushN(data.h);
L!pushN(data.l);

  if (regs.e) {
    regs.s.h = 0x01;
  }
}

// Op Table
// --------

auto callB(string op)(ubyte data) {
  mixin("return op" ~ op ~ "B(data);");
}
auto callW(string op)(ushort data) {
  mixin("return op" ~ op ~ "W(data);");
}

auto ref register(string r)() {
  static if (r == "") {
    return 0;
  }
  else {
    return mixin("regs." ~ r);
  }
}

void updateTable() {
  auto b = 0;
  if (regs.p.m) {
    if (regs.p.x) {
      b = 0;
      ops = opTable[0].ptr;
    }
    else {
      b = 1;
      ops = opTable[1].ptr;
    }
  }
  else {
    if (regs.p.x) {
      b = 2;
      ops = opTable[2].ptr;
    }
    else {
      b = 3;
      ops = opTable[3].ptr;
    }
  }
}

__gshared Op[0x100][4] opTable;

void opA(ubyte id, string name, args...)() {
  opTable[0][id] = opTable[1][id] = opTable[2][id] = opTable[3][id] = &mixin("op" ~ name);
}

void opAI(ubyte id, string name, args...)() {
  opTable[0][id] = opTable[1][id] = opTable[2][id] = opTable[3][id] = &mixin("op" ~ name ~ "!args");
}

void opM(ubyte id, string name)() {
  opTable[0][id] = opTable[1][id] = &mixin("op" ~ name ~ "B");
  opTable[2][id] = opTable[3][id] = &mixin("op" ~ name ~ "W");
}

void opMI(ubyte id, string name, args...)() {
  opTable[0][id] = opTable[1][id] = &mixin("op" ~ name ~ "B!args");
  opTable[2][id] = opTable[3][id] = &mixin("op" ~ name ~ "W!args");
}

void opX(ubyte id, string name)() {
  opTable[0][id] = opTable[2][id] = &mixin("op" ~ name ~ "B");
  opTable[1][id] = opTable[3][id] = &mixin("op" ~ name ~ "W");
}

void opXI(ubyte id, string name, args...)() {
  opTable[0][id] = opTable[2][id] = &mixin("op" ~ name ~ "B!args");
  opTable[1][id] = opTable[3][id] = &mixin("op" ~ name ~ "W!args");
}

void initTable() {
  opAI!(0x00, "Interrupt", 0xfffe, 0xffe6);
  opMI!(0x01, "IndexedIndirectRead", "Ora");
  opAI!(0x02, "Interrupt", 0xfff4, 0xffe4);
  opMI!(0x03, "StackRead", "Ora");
  opMI!(0x04, "DirectModify", "Tsb");
  opMI!(0x05, "DirectRead", "Ora");
  opMI!(0x06, "DirectModify", "Asl");
  opMI!(0x07, "IndirectLongRead", "Ora");
  opAI!(0x08, "PushB", "p");
  opMI!(0x09, "ImmediateRead",  "Ora");
  opMI!(0x0a, "ImpliedModify", "Asl", "a");
  opA !(0x0b, "PushD");
  opMI!(0x0c, "BankModify",  "Tsb");
  opMI!(0x0d, "BankRead",    "Ora");
  opMI!(0x0e, "BankModify",  "Asl");
  opMI!(0x0f, "LongRead",    "Ora");
  opAI!(0x10, "Branch",      0x80, false);
  opMI!(0x11, "IndirectIndexedRead", "Ora");
  opMI!(0x12, "IndirectRead", "Ora");
  opMI!(0x13, "IndirectStackRead", "Ora");
  opMI!(0x14, "DirectModify", "Trb");
  opMI!(0x15, "DirectRead", "Ora", "x");
  opMI!(0x16, "DirectIndexedModify", "Asl");
  opMI!(0x17, "IndirectLongRead",    "Ora", "y");
  opAI!(0x18, "SetFlag", "c", false);
  opMI!(0x19, "BankRead", "Ora", "y");
  opMI!(0x1a, "ImpliedModify", "Inc", "a");
  opA !(0x1b, "TransferCS");
  opMI!(0x1c, "BankModify", "Trb");
  opMI!(0x1d, "BankRead", "Ora", "x");
  opMI!(0x1e, "BankIndexedModify", "Asl");
  opMI!(0x1f, "LongRead", "Ora", "x");
  opA !(0x20, "CallShort");
  opMI!(0x21, "IndexedIndirectRead", "And");
  opA !(0x22, "CallLong");
  opMI!(0x23, "StackRead",      "And");
  opMI!(0x24, "DirectRead",      "Bit");
  opMI!(0x25, "DirectRead",      "And");
  opMI!(0x26, "DirectModify",    "Rol");
  opMI!(0x27, "IndirectLongRead",    "And");
  opA !(0x28, "PullP");
  opMI!(0x29, "ImmediateRead",   "And");
  opMI!(0x2a, "ImpliedModify", "Rol", "a");
  opA !(0x2b, "PullD");
  opMI!(0x2c, "BankRead",    "Bit");
  opMI!(0x2d, "BankRead",    "And");
  opMI!(0x2e, "BankModify",  "Rol");
  opMI!(0x2f, "LongRead",    "And");
  opAI!(0x30, "Branch",      0x80, true);
  opMI!(0x31, "IndirectIndexedRead",    "And");
  opMI!(0x32, "IndirectRead",     "And");
  opMI!(0x33, "IndirectStackRead",    "And");
  opMI!(0x34, "DirectRead",      "Bit", "x");
  opMI!(0x35, "DirectRead",      "And", "x");
  opMI!(0x36, "DirectIndexedModify", "Rol");
  opMI!(0x37, "IndirectLongRead", "And", "y");
  opAI!(0x38, "SetFlag", "c", true);
  opMI!(0x39, "BankRead",   "And", "y");
  opMI!(0x3a, "ImpliedModify", "Dec", "a");
  opAI!(0x3b, "TransferW", "s", "a");
  opMI!(0x3c, "BankRead", "Bit", "x");
  opMI!(0x3d, "BankRead", "And", "x");
  opMI!(0x3e, "BankIndexedModify", "Rol");
  opMI!(0x3f, "LongRead", "And", "x");
  opA !(0x40, "ReturnInterrupt");
  opMI!(0x41, "IndexedIndirectRead", "Eor");
  opA !(0x42, "Prefix");
  opMI!(0x43, "StackRead", "Eor");
  opXI!(0x44, "BlockMove", -1);
  opMI!(0x45, "DirectRead",      "Eor");
  opMI!(0x46, "DirectModify",    "Lsr");
  opMI!(0x47, "IndirectLongRead",    "Eor");
  opMI!(0x48, "Push",        "a");
  opMI!(0x49, "ImmediateRead",   "Eor");
  opMI!(0x4a, "ImpliedModify", "Lsr", "a");
  opAI!(0x4b, "PushB", "pc.b");
  opA !(0x4c, "JumpShort");
  opMI!(0x4d, "BankRead",    "Eor");
  opMI!(0x4e, "BankModify",  "Lsr");
  opMI!(0x4f, "LongRead",    "Eor");
  opAI!(0x50, "Branch", 0x40, false);
  opMI!(0x51, "IndirectIndexedRead", "Eor");
  opMI!(0x52, "IndirectRead", "Eor");
  opMI!(0x53, "IndirectStackRead", "Eor");
  opXI!(0x54, "BlockMove", +1);
  opMI!(0x55, "DirectRead", "Eor", "x");
  opMI!(0x56, "DirectIndexedModify", "Lsr");
  opMI!(0x57, "IndirectLongRead", "Eor", "y");
  opAI!(0x58, "SetFlag", "i", false);
  opMI!(0x59, "BankRead", "Eor", "y");
  opXI!(0x5a, "Push", "y");
  opAI!(0x5b, "TransferW", "a", "d");
  opA !(0x5c, "JumpLong");
  opMI!(0x5d, "BankRead", "Eor", "x");
  opMI!(0x5e, "BankIndexedModify", "Lsr");
  opMI!(0x5f, "LongRead", "Eor", "x");
  opA !(0x60, "ReturnShort");
  opMI!(0x61, "IndexedIndirectRead", "Adc");
  opA !(0x62, "PushEffectiveRelativeAddress");
  opMI!(0x63, "StackRead", "Adc");
  opMI!(0x64, "DirectWrite", "z");
  opMI!(0x65, "DirectRead", "Adc");
  opMI!(0x66, "DirectModify", "Ror");
  opMI!(0x67, "IndirectLongRead", "Adc");
  opMI!(0x68, "Pull", "a");
  opMI!(0x69, "ImmediateRead", "Adc");
  opMI!(0x6a, "ImpliedModify", "Ror", "a");
  opA !(0x6b, "ReturnLong");
  opA !(0x6c, "JumpIndirect");
  opMI!(0x6d, "BankRead", "Adc");
  opMI!(0x6e, "BankModify", "Ror");
  opMI!(0x6f, "LongRead", "Adc");
  opAI!(0x70, "Branch", 0x40, true);
  opMI!(0x71, "IndirectIndexedRead", "Adc");
  opMI!(0x72, "IndirectRead", "Adc");
  opMI!(0x73, "IndirectStackRead", "Adc");
  opMI!(0x74, "DirectWrite", "z", "x");
  opMI!(0x75, "DirectRead", "Adc", "x");
  opMI!(0x76, "DirectIndexedModify", "Ror");
  opMI!(0x77, "IndirectLongRead", "Adc", "y");
  opAI!(0x78, "SetFlag", "i", true);
  opMI!(0x79, "BankRead", "Adc", "y");
  opXI!(0x7a, "Pull", "y");
  opAI!(0x7b, "TransferW", "d", "a");
  opA !(0x7c, "JumpIndexedIndirect");
  opMI!(0x7d, "BankRead", "Adc", "x");
  opMI!(0x7e, "BankIndexedModify", "Ror");
  opMI!(0x7f, "LongRead", "Adc", "x");
  opAI!(0x80, "Branch");
  opM !(0x81, "IndexedIndirectWrite");
  opA !(0x82, "BranchLong");
  opM !(0x83, "StackWrite");
  opXI!(0x84, "DirectWrite", "y");
  opMI!(0x85, "DirectWrite", "a");
  opXI!(0x86, "DirectWrite", "x");
  opMI!(0x87, "IndirectLongWrite");
  opXI!(0x88, "ImpliedModify", "Dec", "y");
  opM !(0x89, "BitImmediate");
  opMI!(0x8a, "Transfer", "x", "a");
  opAI!(0x8b, "PushB", "b");
  opXI!(0x8c, "BankWrite", "y");
  opMI!(0x8d, "BankWrite", "a");
  opXI!(0x8e, "BankWrite", "x");
  opMI!(0x8f, "LongWrite", "a");
  opAI!(0x90, "Branch", 0x01, false);
  opM !(0x91, "IndirectIndexedWrite");
  opMI!(0x92, "IndirectWrite");
  opM !(0x93, "IndirectStackWrite");
  opXI!(0x94, "DirectWrite", "y", "x");
  opMI!(0x95, "DirectWrite", "a", "x");
  opXI!(0x96, "DirectWrite", "x", "y");
  opMI!(0x97, "IndirectLongWrite", "y");
  opMI!(0x98, "Transfer", "y", "a");
  opMI!(0x99, "BankWrite", "a", "y");
  opA !(0x9a, "TransferXS");
  opXI!(0x9b, "Transfer", "x", "y");
  opMI!(0x9c, "BankWrite", "z");
  opMI!(0x9d, "BankWrite", "a", "x");
  opMI!(0x9e, "BankWrite", "z", "x");
  opMI!(0x9f, "LongWrite", "x");
  opXI!(0xa0, "ImmediateRead", "Ldy");
  opMI!(0xa1, "IndexedIndirectRead", "Lda");
  opXI!(0xa2, "ImmediateRead", "Ldx");
  opMI!(0xa3, "StackRead", "Lda");
  opXI!(0xa4, "DirectRead", "Ldy");
  opMI!(0xa5, "DirectRead", "Lda");
  opXI!(0xa6, "DirectRead", "Ldx");
  opMI!(0xa7, "IndirectLongRead", "Lda");
  opXI!(0xa8, "Transfer", "a", "y");
  opMI!(0xa9, "ImmediateRead", "Lda");
  opXI!(0xaa, "Transfer", "a", "x");
  opAI!(0xab, "PullB", "b");
  opXI!(0xac, "BankRead", "Ldy");
  opMI!(0xad, "BankRead", "Lda");
  opXI!(0xae, "BankRead", "Ldx");
  opMI!(0xaf, "LongRead", "Lda");
  opAI!(0xb0, "Branch", 0x01, true);
  opMI!(0xb1, "IndirectIndexedRead", "Lda");
  opMI!(0xb2, "IndirectRead", "Lda");
  opMI!(0xb3, "IndirectStackRead", "Lda");
  opXI!(0xb4, "DirectRead", "Ldy", "x");
  opMI!(0xb5, "DirectRead", "Lda", "x");
  opXI!(0xb6, "DirectRead", "Ldx", "y");
  opMI!(0xb7, "IndirectLongRead", "Lda", "y");
  opAI!(0xb8, "SetFlag", "v", false);
  opMI!(0xb9, "BankRead", "Lda", "y");
  opX !(0xba, "TransferSX");
  opXI!(0xbb, "Transfer", "y", "x");
  opXI!(0xbc, "BankRead", "Ldy", "x");
  opMI!(0xbd, "BankRead", "Lda", "x");
  opXI!(0xbe, "BankRead", "Ldx", "y");
  opMI!(0xbf, "LongRead", "Lda", "x");
  opXI!(0xc0, "ImmediateRead", "Cpy");
  opMI!(0xc1, "IndexedIndirectRead", "Cmp");
  opAI!(0xc2, "PFlag", false);
  opMI!(0xc3, "StackRead", "Cmp");
  opXI!(0xc4, "DirectRead", "Cpy");
  opMI!(0xc5, "DirectRead", "Cmp");
  opMI!(0xc6, "DirectModify", "Dec");
  opMI!(0xc7, "IndirectLongRead", "Cmp");
  opXI!(0xc8, "ImpliedModify", "Inc", "y");
  opMI!(0xc9, "ImmediateRead", "Cmp");
  opXI!(0xca, "ImpliedModify", "Dec", "x");
  opA !(0xcb, "Wait");
  opXI!(0xcc, "BankRead", "Cpy");
  opMI!(0xcd, "BankRead", "Cmp");
  opMI!(0xce, "BankModify", "Dec");
  opMI!(0xcf, "LongRead", "Cmp");
  opAI!(0xd0, "Branch", 0x02, false);
  opMI!(0xd1, "IndirectIndexedRead", "Cmp");
  opMI!(0xd2, "IndirectRead", "Cmp");
  opMI!(0xd3, "IndirectStackRead", "Cmp");
  opA !(0xd4, "PushEffectiveIndirectAddress");
  opMI!(0xd5, "DirectRead", "Cmp", "x");
  opMI!(0xd6, "DirectIndexedModify", "Dec");
  opMI!(0xd7, "IndirectLongRead", "Cmp", "y");
  opAI!(0xd8, "SetFlag", "d", false);
  opMI!(0xd9, "BankRead", "Cmp", "y");
  opXI!(0xda, "Push", "x");
  opA !(0xdb, "Stop");
  opA !(0xdc, "JumpIndirectLong");
  opMI!(0xdd, "BankRead", "Cmp", "x");
  opMI!(0xde, "BankIndexedModify", "Dec");
  opMI!(0xdf, "LongRead", "Cmp", "x");
  opXI!(0xe0, "ImmediateRead", "Cpx");
  opMI!(0xe1, "IndexedIndirectRead", "Sbc");
  opAI!(0xe2, "PFlag", true);
  opMI!(0xe3, "StackRead", "Sbc");
  opXI!(0xe4, "DirectRead", "Cpx");
  opMI!(0xe5, "DirectRead", "Sbc");
  opMI!(0xe6, "DirectModify", "Inc");
  opMI!(0xe7, "IndirectLongRead", "Sbc");
  opXI!(0xe8, "ImpliedModify", "Inc", "x");
  opMI!(0xe9, "ImmediateRead", "Sbc");
  opA !(0xea, "NoOperation");
  opA !(0xeb, "ExchangeBA");
  opXI!(0xec, "BankRead", "Cpx");
  opMI!(0xed, "BankRead", "Sbc");
  opMI!(0xee, "BankModify", "Inc");
  opMI!(0xef, "LongRead", "Sbc");
  opAI!(0xf0, "Branch", 0x02, true);
  opMI!(0xf1, "IndirectIndexedRead", "Sbc");
  opMI!(0xf2, "IndirectRead", "Sbc");
  opMI!(0xf3, "IndirectStackRead", "Sbc");
  opA !(0xf4, "PushEffectiveAddress");
  opMI!(0xf5, "DirectRead", "Sbc", "x");
  opMI!(0xf6, "DirectIndexedModify", "Inc");
  opMI!(0xf7, "IndirectLongRead", "Sbc", "y");
  opAI!(0xf8, "SetFlag", "d", true);
  opMI!(0xf9, "BankRead", "Sbc", "y");
  opXI!(0xfa, "Pull", "x");
  opA !(0xfb, "ExchangeCE");
  opA !(0xfc, "CallIndexedIndirect");
  opMI!(0xfd, "BankRead", "Sbc", "x");
  opMI!(0xfe, "BankIndexedModify", "Inc");
  opMI!(0xff, "LongRead", "Sbc", "x");
}
