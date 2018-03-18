/**
 * References:
 *   https://gitlab.com/higan/higan/blob/master/higan/processor/spc700
 *   https://gitlab.com/higan/higan/tree/master/higan/sfc/smp
 */
module snes.smp;

import std.bitmanip : bitfields;

import emulator.util : Reg16;
import thread = emulator.thread;

import cpu = snes.cpu;
import dsp = snes.dsp;

debug {
  import core.stdc.stdio : printf;

  debug = SMP;
}

private __gshared {
  thread.Processor proc;

  IO io;
  Timer!192 timer0;
  Timer!192 timer1;
  Timer!24  timer2;
  ubyte[64] iplrom;
}

package __gshared {
  ubyte[64 * 1024] apuram;
}

nothrow @nogc {
  thread.Processor processor() { return proc; }
}

struct IO {
  // $00f4-$00f7
  union {
    ubyte[4] io; alias io this;
    struct {
      mixin(bitfields!(bool,  "timersDisable", 1,
                       bool,  "ramWritable",   1,
                       bool,  "ramDisable",    1,
                       bool,  "timersEnable",  1,
                       ubyte, "timerSpeed",    2,
                       ubyte, "clockSpeed",    2));
      mixin(bitfields!(bool, "timer0Enable", 1,
                       bool, "timer1Enable", 1,
                       bool, "timer2Enable", 1,
                       bool, "unused1",      1,
                       bool, "write01",      1,
                       bool, "write23",      1,
                       bool, "unused2",      1,
                       bool, "iplromEnable", 1));
      ubyte dspAddr;
      ubyte dspData;
    }
  }
  // $00f8-$00f9
  union {
    ubyte[2] aux;
    struct { ubyte ram00f8, ram00f9; }
  }

  // Timing
  uint clockCounter;
  uint dspCounter;
  uint timerStep;
}

void initialize() {}
void terminate() {}

void power() {
  proc = thread.create(&entry, 32040.0 * 768.0);

  PC = 0x0000;
  YA = 0x0000;
  X = 0x00;
  S = 0xef;
  P = 0x02;

  regs.wait = false;
  regs.stop = false;

  // TODO: Randomize apuram
  apuram[0x00f4] = 0x00;
  apuram[0x00f5] = 0x00;
  apuram[0x00f6] = 0x00;
  apuram[0x00f7] = 0x00;

  io.clockCounter = 0;
  io.dspCounter = 0;
  io.timerStep = 3;

  // $00f0
  io.clockSpeed = 0;
  io.timerSpeed = 0;
  io.timersEnable = true;
  io.ramDisable = false;
  io.ramWritable = true;
  io.timersDisable = false;

  // $00f1
  io.iplromEnable = true;

  // $00f2
  io.dspAddr = 0x00;

  // $00f8-00f9
  io.ram00f8 = 0x00;
  io.ram00f9 = 0x00;

  timer0.power();
  timer1.power();
  timer2.power();
}

void serialize() {
  assert(0);
}

bool synchronizing() nothrow @nogc {
  return false; // TODO
}

private void entry() {
  debug (SMP) printf("smp.entry\n");
  while (true) {
    thread.synchronize();
    instruction();
  }
}

nothrow @nogc:

// Memory
// -----------------------------------------------------------------------------

ubyte readRAM(ushort addr) {
  if (addr >= 0xffc0 && io.iplromEnable) return iplrom[addr & 0x3f];
  if (io.ramDisable) return 0x5a; // 0xff on mini-SNES.
  return apuram[addr];
}

void writeRAM(ushort addr, ubyte data) {
  // Writes to $ffc0-ffff always go to apuram, even if the iplrom is enabled.
  if (io.ramWritable && !io.ramDisable) apuram[addr] = data;
}

ubyte readPort(ubyte port) {
  return apuram[0xf4 + (port & 3)];
}

void writePort(ubyte port, ubyte data) {
  apuram[0xf4 + (port & 3)] = data;
}

ubyte readBus(ushort addr) {
  switch (addr) {
  case 0xf0: .. case 0xf1: return 0x00; // TEST, CONTROL

  case 0xf2: return io.dspAddr;              // DSPADDR
  case 0xf3: return read(io.dspAddr & 0x7f); // DSPDATA

  case 0xf4: .. case 0xf7: // CPUIO0, CPUIO1, CPUIO2, CPUIO3
    processor.synchronize(cpu.processor);
    return readPort(addr & 2);

  case 0xf8: return io.ram00f8; // RAM0
  case 0xf9: return io.ram00f9; // RAM1

  case 0xfa: .. case 0xfc: return 0x00; // T1TARGET, T2TARGET, T2TARGET

  case 0xfd: return timer0.read(); // T0OUT
  case 0xfe: return timer1.read(); // T0OUT
  case 0xff: return timer2.read(); // T0OUT

  default: return readRAM(addr);
  }
}

void writeBus(ushort addr, ubyte data) {
  switch (addr) {
  default: break;

  case 0xf0: // TEST
    if (P.p) break; // Only valid when P flag is clear.

    io[0] = data;
    io.timerStep = (1 << io.clockSpeed) + (2 << io.timerSpeed);

    timer0.synchronizeStage1();
    timer1.synchronizeStage1();
    timer2.synchronizeStage1();
    break;

  case 0xf1: // CONTROL
    io[1] = data;

    if (data & 0x30) {
      // One-time clearing of APU port read registers,
      // emulated by simulating CPU writes of 0x00
      processor.synchronize(cpu.processor);
      if (data & 0x20) {
        // cpu.writePort(2, 0x00);
        // cpu.writePort(3, 0x00);
      }
      else {
        // cpu.writePort(0, 0x00);
        // cpu.writePort(1, 0x00);
      }
      assert(0);
    }

    // 0->1 transition resets timers
    if (!timer2.enable && io.timer2Enable) {
      timer2.stage2 = 0;
      timer2.stage3 = 0;
    }

    if (!timer1.enable && io.timer1Enable) {
      timer1.stage2 = 0;
      timer1.stage3 = 0;
    }

    if (!timer0.enable && io.timer0Enable) {
      timer0.stage2 = 0;
      timer0.stage3 = 0;
    }
    break;

  case 0xf2: // DSPADDR
    io.dspAddr = data;
    break;

  case 0xf3: // DSPDATA
    if (io.dspAddr & 0x80) break; // 0x80-ff are read-only mirrors of 0x00-7f.
    write(io.dspAddr & 0x7f, data);
    break;

  case 0xf4: .. case 0xf7: // CPUIO0, CPUIO1, CPUIO2, CPUIO3
    processor.synchronize(cpu.processor);
    writePort(addr & 2, data);
    break;

  case 0xf8: io.ram00f8 = data; break;// RAM0
  case 0xf9: io.ram00f9 = data; break;// RAM1

  case 0xfa: timer0.target = data; break; // T0TARGET
  case 0xfb: timer1.target = data; break; // T1TARGET
  case 0xfc: timer2.target = data; break; // T2TARGET

  case 0xfd: .. case 0xff: // T0OUT, T1OUT, T2OUT
  }

  writeRAM(addr, data); // All writes, even to MMIO registers, appear on bus.
}

void idle() {
  step(24);
  cycleEdge();
}

ubyte read(ushort addr) {
  step(12);
  auto data = readBus(addr);
  step(12);
  cycleEdge();
  return data;
}

void write(ushort addr, ubyte data) {
  step(24);
  writeBus(addr, data);
  cycleEdge();
}

ubyte readOP(ushort addr) {
  if ((addr & 0xfff0) == 0x00f0) return 0x00;
  if ((addr & 0xffc0) == 0xffc0 && io.iplromEnable) return iplrom[addr & 0x3f];
  return apuram[addr];
}

// Timing
// -----------------------------------------------------------------------------

void step(uint clocks) {
  processor.step(clocks);
  processor.synchronize(dsp.processor);

  version (Debugger) processor.synchronize(cpu.processor);
  else if (processor.clock - cpu.processor.clock > thread.second / 1000) {
    processor.synchronize(cpu.processor);
  }
}

void cycleEdge() {
  timer0.tick();
  timer1.tick();
  timer2.tick();

  // TEST register S-SMP speed control
  // 24 clocks have already been added for this cycle at this point.
  switch (io.clockSpeed) {
  case 0: break;               // 100% speed
  case 1: step(24); break;     //  50% speed
  case 2: for (;;) step(24);   //   0% speed - Locks S-SMP
  case 3: step(24 * 9); break; //  10% speed
  default: assert(0);
  }
}

struct Timer(uint frequency) {
  ubyte stage0;
  ubyte stage1;
  ubyte stage2;
  union {
    ubyte stages;
    mixin(bitfields!(ubyte, "stage3", 4,
                     bool,  "line",   1,
                     bool,  "enable", 1,
                     ubyte, "unused", 2));
  }
  ubyte target;

  nothrow @nogc:

  void power() {
    stage0 = 0;
    stage1 = 0;
    stage2 = 0;
    stages = 0;
    target = 0;
  }

  ubyte read() {
    auto result = stage3;
    stage3 = 0;
    return result;
  }

  void tick() {
    // Stage 0 increment
    stage0 += io.timerStep;
    if (stage0 < frequency) return;
    stage0 -= frequency;

    // Stage 1 increment
    stage1 ^= 1;
    synchronizeStage1();
  }

  void synchronizeStage1() {
    auto newLine = stage1 && io.timersEnable && !io.timersDisable;
    auto oldLine = line;

    line = newLine;
    if (!oldLine && newLine) return; // Only pulse on 1->0 transition.

    // Stage 2 increment
    if (!enable || ++stage2 != target) return;

    // Stage 3 increment
    stage2 = 0;
    stage3 = cast(ubyte) (stage3 + 1);
  }
}

// SPC700 Processor
// -----------------------------------------------------------------------------

private __gshared {
  Registers regs;
  Reg16 dp, sp, rd, wr, bit, ya;
  ubyte opcode;
}

union Flags {
  ubyte data; alias data this;
  mixin(bitfields!(bool, "c", 1,   // Carry
                   bool, "z", 1,   // Zero
                   bool, "i", 1,   // Interrupt disable
                   bool, "h", 1,   // Half-carry
                   bool, "b", 1,   // Break
                   bool, "p", 1,   // Page
                   bool, "v", 1,   // Overflow
                   bool, "n", 1)); // Negative
}

struct Registers {
  Reg16 pc;
  Reg16 ya;
  ubyte x, s;
  Flags p;

  bool wait;
  bool stop;
}

alias fps = ubyte function(ubyte);
alias fpb = ubyte function(ubyte, ubyte);
alias fpw = ushort function(ushort, ushort);

ubyte fetch() {
  return read(PC++);
}

ubyte load(ubyte addr) {
  return read(P.p << 8 | addr);
}

void store(ubyte addr, ubyte data) {
  write(P.p << 8 | addr, data);
}

ubyte pull() {
  return read(0x0100 | ++S);
}

void push(ubyte data) {
  write(0x100 | S--, data);
}

// SPC700 Algorithms
// -----------------------------------------------------------------------------

ubyte adc(ubyte x, ubyte y) {
  auto z = x + y + P.c;
  P.c = z > 0xff;
  P.z = cast(ubyte) z == 0;
  P.h = ((x ^ y ^ z) & 0x10) != 0;
  P.v = (~(x ^ y) & (x ^ z) & 0x80) != 0;
  P.n = (z & 0x80) != 0;
  return cast(ubyte) z;
}

ubyte and(ubyte x, ubyte y) {
  x &= y;
  P.z = x == 0;
  P.n = (x & 0x80) != 0;
  return x;
}

ubyte asl(ubyte x) {
  P.c = (x & 0x80) != 0;
  x <<= 1;
  P.z = x == 0;
  P.n = (x & 0x80) != 0;
  return x;
}

ubyte cmp(ubyte x, ubyte y) {
  auto z = x - y;
  P.c = z >= 0;
  P.z = cast(ubyte) z == 0;
  P.n = (z & 0x80) != 0;
  return x;
}

ubyte dec(ubyte x) {
  x--;
  P.z = x == 0;
  P.n = (x & 0x80) != 0;
  return x;
}

ubyte eor(ubyte x, ubyte y) {
  x ^= y;
  P.z = x == 0;
  P.n = (x & 0x80) != 0;
  return x;
}

ubyte inc(ubyte x) {
  x++;
  P.z = x == 0;
  P.n = (x & 0x80) != 0;
  return x;
}

ubyte ld(ubyte x, ubyte y) {
  P.z = y == 0;
  P.n = (y & 0x80) != 0;
  return y;
}

ubyte lsr(ubyte x) {
  P.c = x & 0x01;
  x >>= 1;
  P.z = x == 0;
  P.n = (x & 0x80) != 0;
  return x;
}

ubyte or(ubyte x, ubyte y) {
  x |= y;
  P.z = x == 0;
  P.n = (x & 0x80) != 0;
  return x;
}

ubyte rol(ubyte x) {
  auto carry = P.c;
  P.c = (x & 0x80) != 0;
  x = cast(ubyte) ((x << 1) | carry);
  P.z = x == 0;
  P.n = (x & 0x80) != 0;
  return x;
}

ubyte ror(ubyte x) {
  ubyte carry = P.c << 7;
  P.c = x & 0x01;
  x = carry | (x >> 1);
  P.z = x == 0;
  P.n = (x & 0x80) != 0;
  return x;
}

ubyte sbc(ubyte x, ubyte y) {
  return adc(x, ~y);
}

//

ushort adw(ushort x, ushort y) {
  Reg16 z;
  P.c = 0;
  z.l = adc(cast(ubyte) x, cast(ubyte) y);
  z.h = adc(x >> 8, y >> 8);
  P.z = z == 0;
  return z;
}

ushort cpw(ushort x, ushort y) {
  auto z = x - y;
  P.c = z >= 0;
  P.z = cast(ushort) z == 0;
  P.n = (z & 0x8000) != 0;
  return x;
}

ushort ldw(ushort x, ushort y) {
  P.z = y == 0;
  P.n = (y & 0x8000) != 0;
  return y;
}

ushort sbw(ushort x, ushort y) {
  Reg16 z;
  P.c = 1;
  z.l = sbc(cast(ubyte) x, cast(ubyte) y);
  z.h = sbc(x >> 8, y >> 8);
  P.z = z == 0;
  return z;
}

// SPC700 Instructions
// -----------------------------------------------------------------------------

void absoluteBitModify(ubyte mode) {
  Reg16 address;
  address.l = fetch();
  address.h = fetch();
  auto bit = address >> 13;
  address &= 0x1fff;
  auto data = read(address);
  auto c = P.c;
  auto b = data & (1 << bit);
  final switch (mode) {
  case 0:  //or  addr:bit
    idle();
    c |= b != 0;
    break;
  case 1:  //or !addr:bit
    idle();
    c |= b == 0;
    break;
  case 2:  //and  addr:bit
    c &= b != 0;
    break;
  case 3:  //and !addr:bit
    c &= b == 0;
    break;
  case 4:  //eor  addr:bit
    idle();
    c ^= b != 0;
    break;
  case 5:  //ld  addr:bit
    c = b != 0;
    break;
  case 6:  //st  addr:bit
    idle();
    write(dp, cast(ubyte) (P.c << bit));
    break;
  case 7:  //not  addr:bit
    write(dp, cast(ubyte) (data ^= 1 << bit));
    break;
  }
  P.c = c;
}

void absoluteBitSet(ubyte bit, bool value) {
  auto addr = fetch();
  auto data = load(addr);
  if (value) data |= 1 << bit;
  else data &= ~(1 << bit);
  store(addr, data);
}

void absoluteRead(alias op)(ref ubyte target) {
  Reg16 address;
  address.l = fetch();
  address.h = fetch();
  auto data = read(address);
  target = op(target, data);
}

void absoluteModify(alias op)() {
  Reg16 address;
  address.l = fetch();
  address.h = fetch();
  auto data = read(address);
  write(address, op(data));
}

void absoluteWrite(ubyte data) {
  Reg16 address;
  address.l = fetch();
  address.h = fetch();
  read(address);
  write(address, data);
}

void absoluteIndexedRead(alias op)(ubyte index) {
  Reg16 address;
  address.l = fetch();
  address.h = fetch();
  address += index;
  idle();
  auto data = read(address);
  A = op(A, data);
}

void absoluteIndexedWrite(ubyte index) {
  Reg16 address;
  address.l = fetch();
  address.h = fetch();
  address += index;
  idle();
  read(address);
  write(address, A);
}

void branch(bool take) {
  auto displacement = fetch();
  if (!take) return;
  idle();
  idle();
  PC += cast(byte) displacement;
}

void branchBit(ubyte bit, bool match) {
  auto address = fetch();
  auto data = load(address);
  idle();
  auto displacement = fetch();
  if (((data & (1 << bit)) != 0) != match) return;
  idle();
  idle();
  PC += cast(byte) displacement;
}

void branchNotDirect() {
  auto address = fetch();
  auto data = load(address);
  idle();
  auto displacement = fetch();
  if (A == data) return;
  idle();
  idle();
  PC += cast(byte) displacement;
}

void branchNotDirectDecrement() {
  auto address = fetch();
  auto data = load(address);
  store(address, --data);
  auto displacement = fetch();
  if (data == 0) return;
  idle();
  idle();
  PC += cast(byte) displacement;
}

void branchNotDirectIndexed(ref ubyte index) {
  auto address = fetch();
  idle();
  auto data = load(cast(ubyte) (address + index));
  idle();
  auto displacement = fetch();
  if(A == data) return;
  idle();
  idle();
  PC += cast(byte) displacement;
}

void branchNotYDecrement() {
  read(PC);
  idle();
  auto displacement = fetch();
  if(--Y == 0) return;
  idle();
  idle();
  PC += cast(byte) displacement;
}

void break_() {
  read(PC);
  push(PC.h);
  push(PC.l);
  push(P);
  idle();
  Reg16 address;
  address.l = read(0xffde);
  address.h = read(0xffdf);
  PC = address;
  P.i = false;
  P.b = true;
}

void callAbsolute() {
  Reg16 address;
  address.l = fetch();
  address.h = fetch();
  idle();
  push(PC.h);
  push(PC.l);
  idle();
  idle();
  PC = address;
}

void callTable(ubyte vector) {
  read(PC);
  idle();
  push(PC.h);
  push(PC.l);
  idle();
  ushort address = 0xffde - (vector << 1);
  Reg16 pc;
  pc.l = read(cast(ushort) (address + 0));
  pc.h = read(cast(ushort) (address + 1));
  PC = pc;
}

void complementCarry() {
  read(PC);
  idle();
  P.c = !P.c;
}

void decimalAdjustAdd() {
  read(PC);
  idle();
  if (P.c || (A) > 0x99) {
    A += 0x60;
    P.c = true;
  }
  if (P.h || (A & 15) > 0x09) {
    A += 0x06;
  }
  P.z = A == 0;
  P.n = (A & 0x80) != 0;
}

void decimalAdjustSub() {
  read(PC);
  idle();
  if (!P.c || A > 0x99) {
    A -= 0x60;
    P.c = false;
  }
  if (!P.h || (A & 15) > 0x09) {
    A -= 0x06;
  }
  P.z = A == 0;
  P.n = (A & 0x80) != 0;
}

void directRead(alias op)(ref ubyte target) {
  auto address = fetch();
  auto data = load(address);
  target = op(target, data);
}

void directModify(alias op)() {
  auto address = fetch();
  auto data = load(address);
  store(address, op(data));
}

void directWrite(ubyte data) {
  auto address = fetch();
  load(address);
  store(address, data);
}

void directDirectCompare(alias op)() {
  auto source = fetch();
  auto rhs = load(source);
  auto target = fetch();
  auto lhs = load(target);
  op(lhs, rhs);
  load(target);
}

void directDirectModify(alias op)() {
  auto source = fetch();
  auto rhs = load(source);
  auto target = fetch();
  auto lhs = load(target);
  store(target, op(lhs, rhs));
}

void directDirectWrite() {
  auto source = fetch();
  auto data = load(source);
  auto target = fetch();
  store(target, data);
}

void directImmediateCompare(alias op)() {
  auto immediate = fetch();
  auto address = fetch();
  auto data = load(address);
  op(data, immediate);
  load(address);
}

void directImmediateModify(alias op)() {
  auto immediate = fetch();
  auto address = fetch();
  auto data = load(address);
  store(address, op(data, immediate));
}

void directImmediateWrite() {
  auto immediate = fetch();
  auto address = fetch();
  load(address);
  store(address, immediate);
}

void directCompareWord(alias op)() {
  auto address = fetch();
  Reg16 data;
  data.l = load(cast(ubyte) (address + 0));
  data.h = load(cast(ubyte) (address + 1));
  YA = op(YA, data);
}

void directReadWord(alias op)() {
  auto address = fetch();
  Reg16 data;
  data.l = load(cast(ubyte) (address + 0));
  idle();
  data.h = load(cast(ubyte) (address + 1));
  YA = op(YA, data);
}

void directModifyWord(int adjust) {
  auto address = fetch();
  Reg16 data;
  data.l = load(address);
  data.l += adjust;
  store(address, data.l);
  address += 1;
  data.h = load(address);
  store(address, data.h);
  P.z = data == 0;
  P.n = (data & 0x8000) != 0;
}

void directWriteWord() {
  auto address = fetch();
  load(address);
  store(cast(ubyte) (address + 0), A);
  store(cast(ubyte) (address + 1), Y);
}

void directIndexedRead(alias op)(ref ubyte target, ubyte index) {
  auto address = fetch();
  idle();
  auto data = load(cast(ubyte) (address + index));
  target = op(target, data);
}

void directIndexedModify(alias op)(ubyte index) {
  auto address = cast(ubyte) (fetch() + index);
  idle();
  auto data = load(address);
  store(address, op(data));
}

void directIndexedWrite(ubyte data, ubyte index) {
  auto address = cast(ubyte) (fetch() + index);
  idle();
  load(address);
  store(address, data);
}

void divide() {
  read(PC);
  idle();
  idle();
  idle();
  idle();
  idle();
  idle();
  idle();
  idle();
  idle();
  idle();
  auto ya = YA;
  // Overflow set if quotient >= 256
  P.h = ((Y & 15) >= (X & 15));
  P.v = Y >= X;
  if (Y < (X << 1)) {
    // If quotient is <= 511 (will fit into 9-bit result)
    A = cast(ubyte) (ya / X);
    Y = cast(ubyte) (ya % X);
  }
  else {
    // Otherwise, the quotient won't fit into P.v + A
    // this emulates the odd behavior of the S-SMP in this case
    A = cast(ubyte) (255 - (ya - (X << 9)) / (256 - X));
    Y = cast(ubyte) (X   + (ya - (X << 9)) % (256 - X));
  }
  // Result is set based on a (quotient) only
  P.z = A == 0;
  P.n = (A & 0x80) != 0;
}

void exchangeNibble() {
  read(PC);
  idle();
  idle();
  idle();
  A = cast(ubyte) ((A >> 4) | (A << 4));
  P.z = A == 0;
  P.n = (A & 0x80) != 0;
}

void flagSet(string flag)(bool value) {
  enum f = "P." ~ flag;
  read(PC);
  if (mixin(f) == P.i) idle();
  mixin(f) = value;
}

void immediateRead(alias op)(ref ubyte target) {
  target = op(target, fetch());
}

void impliedModify(alias op)(ref ubyte target) {
  read(PC);
  target = op(target);
}

void indexedIndirectRead(alias op)(ubyte index) {
  auto indirect = fetch();
  idle();
  Reg16 address;
  address.l = load(cast(ubyte) (indirect + index + 0));
  address.h = load(cast(ubyte) (indirect + index + 1));
  auto data = read(address);
  A = op(A, data);
}

void indexedIndirectWrite(ubyte data, ubyte index) {
  auto indirect = fetch();
  idle();
  Reg16 address;
  address.l = load(cast(ubyte) (indirect + index + 0));
  address.h = load(cast(ubyte) (indirect + index + 1));
  read(address);
  write(address, A);
}

void indirectIndexedRead(alias op)(ubyte index) {
  auto indirect = fetch();
  Reg16 address;
  address.l = load(indirect);
  address.h = load(cast(ubyte) (indirect + 1));
  idle();
  auto data = read(cast(ushort) (address + index));
  A = op(A, data);
}

void indirectIndexedWrite(ubyte data, ubyte index) {
  auto indirect = fetch();
  Reg16 address;
  address.l = load(cast(ubyte) (indirect + 0));
  address.h = load(cast(ubyte) (indirect + 1));
  idle();
  address += index;
  read(address);
  write(address, data);
}

void indirectXRead(alias op)() {
  read(PC);
  auto data = load(X);
  A = op(A, data);
}

void indirectXWrite(ubyte data) {
  read(PC);
  load(X);
  store(X, data);
}

void indirectXIncrementRead(ref ubyte data) {
  read(PC);
  data = load(X++);
  idle(); // Quirk: consumes extra idle cycle compared to most read instructions
  P.z = A == 0;
  P.n = (A & 0x80) != 0;
}

void indirectXIncrementWrite(ubyte data) {
  read(PC);
  idle(); // Quirk: not a read cycle as with most write instructions
  store(X++, A);
}

void indirectXWriteIndirectY(alias op)() {
  read(PC);
  auto rhs = load(Y);
  auto lhs = load(X);
  store(X, op(lhs, rhs));
}

void jumpAbsolute() {
  Reg16 address;
  address.l = fetch();
  address.h = fetch();
  PC = address;
}

void jumpIndirectX() {
  Reg16 address;
  address.l = fetch();
  address.h = fetch();
  idle();
  Reg16 pc;
  pc.l = read(cast(ushort) (address + X + 0));
  pc.h = read(cast(ushort) (address + X + 1));
  PC = pc;
}

void multiply() {
  read(PC);
  idle();
  idle();
  idle();
  idle();
  idle();
  idle();
  idle();
  ushort ya = Y * A;
  A = cast(ubyte) ya;
  Y = ya >> 8;
  // Result is set based on y (high-byte) only
  P.z = Y == 0;
  P.n = (Y & 0x80) != 0;
}

void noOperation() {
  read(PC);
}

void overflowClear() {
  idle();
  P.h = false;
  P.v = false;
}

void pullOp(ref ubyte data) {
  read(PC);
  idle();
  data = pull();
}

void pullP() {
  idle();
  idle();
  P = pull();
}

void pushOp(ubyte data) {
  read(PC);
  push(data);
  idle();
}

void returnInterrupt() {
  read(PC);
  idle();
  P = pull();
  Reg16 address;
  address.l = pull();
  address.h = pull();
  PC = address;
}

void returnSubroutine() {
  read(PC);
  idle();
  Reg16 address;
  address.l = pull();
  address.h = pull();
  PC = address;
}

void stop() {
  regs.stop = true;
  while (regs.stop && !synchronizing) {
    read(PC);
    idle();
  }
}

void testSetBitsAbsolute(bool set) {
  Reg16 address;
  address.l = fetch();
  address.h = fetch();
  auto data = read(address);
  P.z = (A - data) == 0;
  P.n = ((A - data) & 0x80) != 0;
  read(address);
  write(address, set ? data | A : data & ~A);
}

void transfer(ubyte from, ref ubyte to) {
  read(PC);
  to = from;
  if (to == S) return;
  P.z = to == 0;
  P.n = (to & 0x80) != 0;
}

void callPage() {
  rd = fetch();
  idle();
  idle();
  push(PC.h);
  push(PC.l);
  PC = 0xff00 | rd;
}

void wait() {
  regs.wait = true;
  while (regs.wait && !synchronizing) {
    read(PC);
    idle();
  }
}

// SPC700 Opcode Table
// -----------------------------------------------------------------------------

void instruction() {
  final switch (opcode = fetch()) {
  case 0x00: return noOperation();
  case 0x01: return callTable(0);
  case 0x02: return absoluteBitSet(0, true);
  case 0x03: return branchBit(0, true);
  case 0x04: return directRead!or(A);
  case 0x05: return absoluteRead!or(A);
  case 0x06: return indirectXRead!or();
  case 0x07: return indexedIndirectRead!or(X);
  case 0x08: return immediateRead!or(A);
  case 0x09: return directDirectModify!or();
  case 0x0a: return absoluteBitModify(0);
  case 0x0b: return directModify!asl();
  case 0x0c: return absoluteModify!asl();
  case 0x0d: return pushOp(P);
  case 0x0e: return testSetBitsAbsolute(true);
  case 0x0f: return break_();
  case 0x10: return branch(P.n == 0);
  case 0x11: return callTable(1);
  case 0x12: return absoluteBitSet(0, false);
  case 0x13: return branchBit(0, false);
  case 0x14: return directIndexedRead!or(A, X);
  case 0x15: return absoluteIndexedRead!or(X);
  case 0x16: return absoluteIndexedRead!or(Y);
  case 0x17: return indirectIndexedRead!or(Y);
  case 0x18: return directImmediateModify!or();
  case 0x19: return indirectXWriteIndirectY!or();
  case 0x1a: return directModifyWord(-1);
  case 0x1b: return directIndexedModify!asl(X);
  case 0x1c: return impliedModify!asl(A);
  case 0x1d: return impliedModify!dec(X);
  case 0x1e: return absoluteRead!cmp(X);
  case 0x1f: return jumpIndirectX();
  case 0x20: return flagSet!"p"(false);
  case 0x21: return callTable(2);
  case 0x22: return absoluteBitSet(1, true);
  case 0x23: return branchBit(1, true);
  case 0x24: return directRead!and(A);
  case 0x25: return absoluteRead!and(A);
  case 0x26: return indirectXRead!and();
  case 0x27: return indexedIndirectRead!and(X);
  case 0x28: return immediateRead!and(A);
  case 0x29: return directDirectModify!and();
  case 0x2a: return absoluteBitModify(1);
  case 0x2b: return directModify!rol();
  case 0x2c: return absoluteModify!rol();
  case 0x2d: return pushOp(A);
  case 0x2e: return branchNotDirect();
  case 0x2f: return branch(true);
  case 0x30: return branch(P.n == 1);
  case 0x31: return callTable(3);
  case 0x32: return absoluteBitSet(1, false);
  case 0x33: return branchBit(1, false);
  case 0x34: return directIndexedRead!and(A, X);
  case 0x35: return absoluteIndexedRead!and(X);
  case 0x36: return absoluteIndexedRead!and(Y);
  case 0x37: return indirectIndexedRead!and(Y);
  case 0x38: return directImmediateModify!and();
  case 0x39: return indirectXWriteIndirectY!and();
  case 0x3a: return directModifyWord(+1);
  case 0x3b: return directIndexedModify!rol(X);
  case 0x3c: return impliedModify!rol(A);
  case 0x3d: return impliedModify!inc(X);
  case 0x3e: return directRead!cmp(X);
  case 0x3f: return callAbsolute();
  case 0x40: return flagSet!"p"(true);
  case 0x41: return callTable(4);
  case 0x42: return absoluteBitSet(2, true);
  case 0x43: return branchBit(2, true);
  case 0x44: return directRead!eor(A);
  case 0x45: return absoluteRead!eor(A);
  case 0x46: return indirectXRead!eor();
  case 0x47: return indexedIndirectRead!eor(X);
  case 0x48: return immediateRead!eor(A);
  case 0x49: return directDirectModify!eor();
  case 0x4a: return absoluteBitModify(2);
  case 0x4b: return directModify!lsr();
  case 0x4c: return absoluteModify!lsr();
  case 0x4d: return pushOp(X);
  case 0x4e: return testSetBitsAbsolute(0);
  case 0x4f: return callPage();
  case 0x50: return branch(P.v == 0);
  case 0x51: return callTable(5);
  case 0x52: return absoluteBitSet(2, false);
  case 0x53: return branchBit(2, false);
  case 0x54: return directIndexedRead!eor(A, X);
  case 0x55: return absoluteIndexedRead!eor(X);
  case 0x56: return absoluteIndexedRead!eor(Y);
  case 0x57: return indirectIndexedRead!eor(Y);
  case 0x58: return directImmediateModify!eor();
  case 0x59: return indirectXWriteIndirectY!eor();
  case 0x5a: return directCompareWord!cpw();
  case 0x5b: return directIndexedModify!lsr(X);
  case 0x5c: return impliedModify!lsr(A);
  case 0x5d: return transfer(A, X);
  case 0x5e: return absoluteRead!cmp(Y);
  case 0x5f: return jumpAbsolute();
  case 0x60: return flagSet!"c"(false);
  case 0x61: return callTable(6);
  case 0x62: return absoluteBitSet(3, true);
  case 0x63: return branchBit(3, true);
  case 0x64: return directRead!cmp(A);
  case 0x65: return absoluteRead!cmp(A);
  case 0x66: return indirectXRead!(cmp);
  case 0x67: return indexedIndirectRead!(cmp)(X);
  case 0x68: return immediateRead!cmp(A);
  case 0x69: return directDirectCompare!cmp;
  case 0x6a: return absoluteBitModify(3);
  case 0x6b: return directModify!ror;
  case 0x6c: return absoluteModify!ror;
  case 0x6d: return pushOp(Y);
  case 0x6e: return branchNotDirectDecrement();
  case 0x6f: return returnSubroutine();
  case 0x70: return branch(P.v == 1);
  case 0x71: return callTable(7);
  case 0x72: return absoluteBitSet(3, false);
  case 0x73: return branchBit(3, false);
  case 0x74: return directIndexedRead!cmp(A, X);
  case 0x75: return absoluteIndexedRead!cmp(X);
  case 0x76: return absoluteIndexedRead!cmp(Y);
  case 0x77: return indirectIndexedRead!cmp(Y);
  case 0x78: return directImmediateCompare!cmp;
  case 0x79: return indirectXWriteIndirectY!cmp;
  case 0x7a: return directReadWord!adw;
  case 0x7b: return directIndexedModify!ror(X);
  case 0x7c: return impliedModify!ror(A);
  case 0x7d: return transfer(X, A);
  case 0x7e: return directRead!cmp(Y);
  case 0x7f: return returnInterrupt();
  case 0x80: return flagSet!"c"(true);
  case 0x81: return callTable(8);
  case 0x82: return absoluteBitSet(4, true);
  case 0x83: return branchBit(4, true);
  case 0x84: return directRead!adc(A);
  case 0x85: return absoluteRead!adc(A);
  case 0x86: return indirectXRead!adc;
  case 0x87: return indexedIndirectRead!adc(X);
  case 0x88: return immediateRead!adc(A);
  case 0x89: return directDirectModify!adc;
  case 0x8a: return absoluteBitModify(4);
  case 0x8b: return directModify!dec;
  case 0x8c: return absoluteModify!dec;
  case 0x8d: return immediateRead!ld(Y);
  case 0x8e: return pullP();
  case 0x8f: return directImmediateWrite();
  case 0x90: return branch(P.c == 0);
  case 0x91: return callTable(9);
  case 0x92: return absoluteBitSet(4, false);
  case 0x93: return branchBit(4, false);
  case 0x94: return directIndexedRead!adc(A, X);
  case 0x95: return absoluteIndexedRead!adc(X);
  case 0x96: return absoluteIndexedRead!adc(Y);
  case 0x97: return indirectIndexedRead!adc(Y);
  case 0x98: return directImmediateModify!adc;
  case 0x99: return indirectXWriteIndirectY!adc;
  case 0x9a: return directReadWord!sbw;
  case 0x9b: return directIndexedModify!dec(X);
  case 0x9c: return impliedModify!dec(A);
  case 0x9d: return transfer(S, X);
  case 0x9e: return divide();
  case 0x9f: return exchangeNibble();
  case 0xa0: return flagSet!"i"(true);
  case 0xa1: return callTable(10);
  case 0xa2: return absoluteBitSet(5, true);
  case 0xa3: return branchBit(5, true);
  case 0xa4: return directRead!sbc(A);
  case 0xa5: return absoluteRead!sbc(A);
  case 0xa6: return indirectXRead!sbc;
  case 0xa7: return indexedIndirectRead!sbc(X);
  case 0xa8: return immediateRead!sbc(A);
  case 0xa9: return directDirectModify!sbc;
  case 0xaa: return absoluteBitModify(5);
  case 0xab: return directModify!inc;
  case 0xac: return absoluteModify!inc;
  case 0xad: return immediateRead!cmp(Y);
  case 0xae: return pullOp(A);
  case 0xaf: return indirectXIncrementWrite(A);
  case 0xb0: return branch(P.c == 1);
  case 0xb1: return callTable(11);
  case 0xb2: return absoluteBitSet(5, false);
  case 0xb3: return branchBit(5, false);
  case 0xb4: return directIndexedRead!sbc(A, X);
  case 0xb5: return absoluteIndexedRead!sbc(X);
  case 0xb6: return absoluteIndexedRead!sbc(Y);
  case 0xb7: return indirectIndexedRead!sbc(Y);
  case 0xb8: return directImmediateModify!sbc;
  case 0xb9: return indirectXWriteIndirectY!sbc;
  case 0xba: return directReadWord!ldw;
  case 0xbb: return directIndexedModify!inc(X);
  case 0xbc: return impliedModify!inc(A);
  case 0xbd: return transfer(X, S);
  case 0xbe: return decimalAdjustSub();
  case 0xbf: return indirectXIncrementRead(A);
  case 0xc0: return flagSet!"i"(false);
  case 0xc1: return callTable(12);
  case 0xc2: return absoluteBitSet(6, true);
  case 0xc3: return branchBit(6, true);
  case 0xc4: return directWrite(A);
  case 0xc5: return absoluteWrite(A);
  case 0xc6: return indirectXWrite(A);
  case 0xc7: return indexedIndirectWrite(A, X);
  case 0xc8: return immediateRead!cmp(X);
  case 0xc9: return absoluteWrite(X);
  case 0xca: return absoluteBitModify(6);
  case 0xcb: return directWrite(Y);
  case 0xcc: return absoluteWrite(Y);
  case 0xcd: return immediateRead!ld(X);
  case 0xce: return pullOp(X);
  case 0xcf: return multiply();
  case 0xd0: return branch(P.z == 0);
  case 0xd1: return callTable(13);
  case 0xd2: return absoluteBitSet(6, false);
  case 0xd3: return branchBit(6, false);
  case 0xd4: return directIndexedWrite(A, X);
  case 0xd5: return absoluteIndexedWrite(X);
  case 0xd6: return absoluteIndexedWrite(A);
  case 0xd7: return indirectIndexedWrite(A, Y);
  case 0xd8: return directWrite(X);
  case 0xd9: return directIndexedWrite(X, Y);
  case 0xda: return directWriteWord();
  case 0xdb: return directIndexedWrite(Y, X);
  case 0xdc: return impliedModify!dec(Y);
  case 0xdd: return transfer(Y, A);
  case 0xde: return branchNotDirectIndexed(X);
  case 0xdf: return decimalAdjustAdd();
  case 0xe0: return overflowClear();
  case 0xe1: return callTable(14);
  case 0xe2: return absoluteBitSet(7, true);
  case 0xe3: return branchBit(7, true);
  case 0xe4: return directRead!ld(A);
  case 0xe5: return absoluteRead!ld(A);
  case 0xe6: return indirectXRead!ld;
  case 0xe7: return indexedIndirectRead!ld(X);
  case 0xe8: return immediateRead!ld(A);
  case 0xe9: return absoluteRead!ld(X);
  case 0xea: return absoluteBitModify(7);
  case 0xeb: return directRead!ld(Y);
  case 0xec: return absoluteRead!ld(Y);
  case 0xed: return complementCarry();
  case 0xee: return pullOp(Y);
  case 0xef: return wait();
  case 0xf0: return branch(P.z == 1);
  case 0xf1: return callTable(15);
  case 0xf2: return absoluteBitSet(7, false);
  case 0xf3: return branchBit(7, false);
  case 0xf4: return directIndexedRead!ld(A, X);
  case 0xf5: return absoluteIndexedRead!ld(X);
  case 0xf6: return absoluteIndexedRead!ld(Y);
  case 0xf7: return indirectIndexedRead!ld(Y);
  case 0xf8: return directRead!ld(X);
  case 0xf9: return directIndexedRead!ld(X, Y);
  case 0xfa: return directDirectWrite();
  case 0xfb: return directIndexedRead!ld(Y, X);
  case 0xfc: return impliedModify!inc(Y);
  case 0xfd: return transfer(A, Y);
  case 0xfe: return branchNotYDecrement();
  case 0xff: return stop();
  }
}

pragma(inline, true):
ref ubyte X() { return regs.x; }
ref ubyte Y() { return YA.h; }
ref ubyte A() { return YA.l; }
ref ubyte S() { return regs.s; }
ref Flags P() { return regs.p; }
ref Reg16 PC() { return regs.pc; }
ref Reg16 YA() { return regs.ya; }
