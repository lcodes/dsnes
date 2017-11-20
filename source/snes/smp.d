module snes.smp;

import std.bitmanip : bitfields;

import thread = emulator.thread;

import emulator.types;

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

  regs.pc.l = iplrom[62];
  regs.pc.h = iplrom[63];
  regs.a = 0x00;
  regs.x = 0x00;
  regs.y = 0x00;
  regs.s = 0xef;
  regs.p = 0x02;

  // Randomize apuram
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

private void entry() {
  debug (SMP) printf("smp.entry\n");
  while (true) {
    thread.synchronize();
    instruction();
  }
}

nothrow @nogc:

// Memory
// -------------------------------------------------------------------------------------------------

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
    if (regs.p.p) break; // Only valid when P flag is clear.

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
// -------------------------------------------------------------------------------------------------

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
// -------------------------------------------------------------------------------------------------

private __gshared {
  Registers regs;
  Reg16 dp, sp, rd, wr, bit, ya;
  ubyte opcode;
}

union Flags {
  ubyte data; alias data this;
  mixin(bitfields!(bool, "c", 1,
                   bool, "z", 1,
                   bool, "i", 1,
                   bool, "h", 1,
                   bool, "b", 1,
                   bool, "p", 1,
                   bool, "v", 1,
                   bool, "n", 1));
}

struct Registers {
  Reg16 pc;
  union {
    ushort ya;
    struct { ubyte a, y; }
  }
  ubyte x, s;
  Flags p;
}

alias fps = ubyte function(ubyte);
alias fpb = ubyte function(ubyte, ubyte);
alias fpw = ushort function(ushort, ushort);

ubyte readPC() {
  return read(regs.pc++);
}

ubyte readSP() {
  return read(0x0100 | ++regs.s);
}

void writeSP(ubyte data) {
  return write(0x100 | regs.s--, data);
}

ubyte readDP(ubyte addr) {
  return read(regs.p.p << 8 | addr);
}

void writeDP(ubyte addr, ubyte data) {
  write(regs.p.p << 8 | addr, data);
}

// SPC700 Algorithms
// -------------------------------------------------------------------------------------------------

ubyte op_adc(ubyte x, ubyte y) {
  auto r = x + y + regs.p.c;
  regs.p.n = (r & 0x80) != 0;
  regs.p.v = (~(x ^ y) & (x ^ r) & 0x80) != 0;
  regs.p.h = ((x ^ y ^ r) & 0x10) != 0;
  regs.p.z = cast(ubyte) r == 0;
  regs.p.c = r > 0xff;
  return cast(ubyte) r;
}

ubyte op_and(ubyte x, ubyte y) {
  x &= y;
  regs.p.n = (x & 0x80) != 0;
  regs.p.z = x == 0;
  return x;
}

ubyte op_asl(ubyte x) {
  regs.p.c = (x & 0x80) != 0;
  x <<= 1;
  regs.p.n = (x & 0x80) != 0;
  regs.p.z = x == 0;
  return x;
}

ubyte op_cmp(ubyte x, ubyte y) {
  auto r = x - y;
  regs.p.n = (r & 0x80) != 0;
  regs.p.z = cast(ubyte) r == 0;
  regs.p.c = r >= 0;
  return x;
}

ubyte op_dec(ubyte x) {
  x--;
  regs.p.n = (x & 0x80) != 0;
  regs.p.z = x == 0;
  return x;
}

ubyte op_eor(ubyte x, ubyte y) {
  x ^= y;
  regs.p.n = (x & 0x80) != 0;
  regs.p.z = x == 0;
  return x;
}

ubyte op_inc(ubyte x) {
  x++;
  regs.p.n = (x & 0x80) != 0;
  regs.p.z = x == 0;
  return x;
}

ubyte op_ld(ubyte x, ubyte y) {
  regs.p.n = (y & 0x80) != 0;
  regs.p.z = y == 0;
  return y;
}

ubyte op_lsr(ubyte x) {
  regs.p.c = x & 0x01;
  x >>= 1;
  regs.p.n = (x & 0x80) != 0;
  regs.p.z = x == 0;
  return x;
}

ubyte op_or(ubyte x, ubyte y) {
  x |= y;
  regs.p.n = (x & 0x80) != 0;
  regs.p.z = x == 0;
  return x;
}

ubyte op_rol(ubyte x) {
  auto carry = regs.p.c;
  regs.p.c = (x & 0x80) != 0;
  x = cast(ubyte) ((x << 1) | carry);
  regs.p.n = (x & 0x80) != 0;
  regs.p.z = x == 0;
  return x;
}

ubyte op_ror(ubyte x) {
  ubyte carry = regs.p.c << 7;
  regs.p.c = x & 0x01;
  x = carry | (x >> 1);
  regs.p.n = (x & 0x80) != 0;
  regs.p.z = x == 0;
  return x;
}

ubyte op_sbc(ubyte x, ubyte y) {
  return op_adc(x, ~y);
}

ubyte op_st(ubyte x, ubyte y) {
  return y;
}

//

ushort op_adw(ushort x, ushort y) {
  ushort r;
  regs.p.c = 0;
  r  = op_adc(cast(ubyte) x, cast(ubyte) y);
  r |= op_adc(x >> 8, y >> 8) << 8;
  regs.p.z = r == 0;
  return r;
}

ushort op_cpw(ushort x, ushort y) {
  auto r = x - y;
  regs.p.n = (r & 0x8000) != 0;
  regs.p.z = cast(ushort) r == 0;
  regs.p.c = r >= 0;
  return x;
}

ushort op_ldw(ushort x, ushort y) {
  regs.p.n = (y & 0x8000) != 0;
  regs.p.z = y == 0;
  return y;
}

ushort op_sbw(ushort x, ushort y) {
  ushort r;
  regs.p.c = 1;
  r  = op_sbc(cast(ubyte) x, cast(ubyte) y);
  r |= op_sbc(x >> 8, y >> 8) << 8;
  regs.p.z = r == 0;
  return r;
}

// SPC700 Instructions
// -------------------------------------------------------------------------------------------------

void op_adjust(alias op, alias r)() {
  idle();
  r = op(r);
}

void op_adjust_addr(alias op)() {
  dp.l = readPC();
  dp.h = readPC();
  rd = read(dp);
  rd = op(rd);
  write(dp, rd);
}

void op_adjust_dp(alias op)() {
  dp = readPC();
  rd = readDP(dp);
  rd = op(rd);
  writeDP(dp, rd);
}

void op_adjust_dpw(int n)() {
  dp = readPC();
  rd.w = readDP(dp) + n;
  writeDP(dp++, rd.l);
  rd.h += readDP(dp);
  writeDP(dp++, rd.h);
  regs.p.n = rd & 0x8000;
  regs.p.z = rd == 0;
}

void op_adjust_dpx(alias op)() {
  dp = readPC();
  idle();
  rd = readDP(dp + regs.x);
  rd = op(rd);
  writeDP(dp + regs.x, rd);
}

void op_branch(bool condition)() {
  rd = readPC();
  if (!condition) return;
  idle();
  idle();
  regs.pc += cast(byte) rd;
}

void op_branch_bit() {
  dp = readPC();
  sp = readDP(cast(ubyte) dp);
  rd = readPC();
  idle();
  if (cast(bool) (sp & (1 << (opcode >> 5))) == cast(bool) (opcode & 0x10)) return;
  idle();
  idle();
  regs.pc += cast(byte) rd;
}

void op_pull(alias r)() {
  idle();
  idle();
  r = readSP();
}

void op_push(alias r)() {
  idle();
  idle();
  writeSP(r);
}

void op_read_addr(alias op, alias r)() {
  dp.l = readPC();
  dp.h = readPC();
  rd = read(dp);
  r = op(r, rd);
}

auto op_read_addri(alias op, alias r)() {
  dp.l = readPC();
  dp.h = readPC();
  idle();
  rd = read(dp + r);
  regs.a = op(regs.a, rd);
}

auto op_read_const(alias op, alias r)() {
  rd = readPC();
  r = op(r, rd);
}

auto op_read_dp(alias op, alias r)() {
  dp = readPC();
  rd = readDP(cast(ubyte) dp);
  r = op(r, cast(ubyte) rd);
}

auto op_read_dpi(alias op, alias r, alias i)() {
  dp = readPC();
  idle();
  rd = readDP(cast(ubyte) dp + i);
  r = op(r, cast(ubyte) rd);
}

void op_read_dpw(alias op)() {
  dp = readPC();
  rd.l = readDP(dp++);
  static if (!is(op == op_cpw)) idle();
  rd.h = readDP(dp++);
  regs.ya = op(regs.ya, rd);
}

void op_read_idpx(alias op)() {
  dp = readPC() + regs.x;
  idle();
  sp.l = readDP(dp++);
  sp.h = readDP(dp++);
  rd = read(sp);
  regs.a = op(regs.a, rd);
}

void op_read_idpy(alias op)() {
  dp = readPC();
  idle();
  sp.l = readDP(dp++);
  sp.h = readDP(dp++);
  rd = read(sp + regs.y);
  regs.a = op(regs.a, rd);
}

void op_read_ix(alias op)() {
  idle();
  rd = readDP(regs.x);
  regs.a = op(regs.a, rd);
}

void op_set_addr_bit() {
  dp.l = readPC();
  dp.h = readPC();
  bit = dp >> 13;
  dp &= 0x1fff;
  rd = read(dp);
  final switch (opcode >> 5) {
  case 0:  //orc  addr:bit
  case 1:  //orc !addr:bit
    idle();
    regs.p.c = regs.p.c || (rd & (1 << bit)) ^ cast(bool) (opcode & 0x20);
    break;
  case 2:  //and  addr:bit
  case 3:  //and !addr:bit
    regs.p.c = regs.p.c & (rd & (1 << bit)) ^ cast(bool) (opcode & 0x20);
    break;
  case 4:  //eor  addr:bit
    idle();
    regs.p.c = regs.p.c ^ cast(bool) (rd & (1 << bit));
    break;
  case 5:  //ldc  addr:bit
    regs.p.c = cast(bool) (rd & (1 << bit));
    break;
  case 6:  //stc  addr:bit
    idle();
    rd = cast(ushort) ((rd & ~(1 << bit)) | (regs.p.c << bit));
    write(dp, cast(ubyte) rd);
    break;
  case 7:  //not  addr:bit
    rd ^= 1 << bit;
    write(dp, cast(ubyte) rd);
    break;
  }
}

void op_set_bit() {
  dp = readPC();
  rd = readDP(cast(ubyte) dp) & ~(1 << (opcode >> 5));
  writeDP(cast(ubyte) dp, cast(ubyte) (rd | (!(opcode & 0x10) << (opcode >> 5))));
}

void op_set_flag(uint bit, bool value)() {
  idle();
  if (bit == regs.p.i.bit) idle();
  regs.p = value ? (regs.p | (1 << bit)) : (regs.p & ~(1 << bit));
}

void op_test_addr(bool set)() {
  dp.l = readPC();
  dp.h = readPC();
  rd = read(dp);
  regs.p.n = (regs.a - rd) & 0x80;
  regs.p.z = (regs.a - rd) == 0;
  read(dp);
  write(dp, set ? rd | regs.a : rd & ~regs.a);
}

void op_transfer(alias from, alias to)() {
  idle();
  to = from;
  if (to == regs.s) return;
  regs.p.n = (to & 0x80) != 0;
  regs.p.z = (to == 0);
}

void op_write_addr(alias r)() {
  dp.l = readPC();
  dp.h = readPC();
  read(dp);
  write(dp, r);
}

void op_write_addri(alias i)() {
  dp.l = readPC();
  dp.h = readPC();
  idle();
  dp += i;
  read(dp);
  write(dp, regs.a);
}

void op_write_dp(alias r)() {
  dp = readPC();
  readDP(dp);
  writeDP(dp, r);
}

void op_write_dpi(alias r, alias i)() {
  dp = readPC() + i;
  idle();
  readDP(dp);
  writeDP(dp, r);
}

void op_write_dp_const(alias op)() {
  rd = readPC();
  dp = readPC();
  wr = readDP(dp);
  wr = op(wr, rd);
  op != &op_cmp ? writeDP(dp, wr) : idle();
}

void op_write_dp_dp(alias op)() {
  sp = readPC();
  rd = readDP(sp);
  dp = readPC();
  static if (!is(op == op_st)) wr = readDP(dp);
  wr = op(wr, rd);
  op != &op_cmp ? writeDP(dp, wr) : idle();
}

void op_write_ix_iy(alias op)() {
  idle();
  rd = readDP(regs.y);
  wr = readDP(regs.x);
  wr = op(wr, rd);
  !is(op == op_cmp) ? writeDP(regs.x, wr) : idle();
}

//

void op_bne_dp() {
  dp = readPC();
  sp = readDP(cast(ubyte) dp);
  rd = readPC();
  idle();
  if (regs.a == sp) return;
  idle();
  idle();
  regs.pc += cast(byte) rd;
}

void op_bne_dpdec() {
  dp = readPC();
  wr = readDP(cast(ubyte) dp);
  writeDP(cast(ubyte) dp, cast(ubyte) --wr);
  rd = readPC();
  if (wr == 0) return;
  idle();
  idle();
  regs.pc += cast(byte) rd;
}

void op_bne_dpx() {
  dp = readPC();
  idle();
  sp = readDP(cast(ubyte) (dp + regs.x));
  rd = readPC();
  idle();
  if(regs.a == sp) return;
  idle();
  idle();
  regs.pc += cast(byte) rd;
}

void op_bne_ydec() {
  rd = readPC();
  idle();
  idle();
  if(--regs.y == 0) return;
  idle();
  idle();
  regs.pc += cast(byte) rd;
}

void op_brk() {
  rd.l = read(0xffde);
  rd.h = read(0xffdf);
  idle();
  idle();
  writeSP(regs.pc.h);
  writeSP(regs.pc.l);
  writeSP(regs.p);
  regs.pc = rd;
  regs.p.b = 1;
  regs.p.i = 0;
}

void op_clv() {
  idle();
  regs.p.v = 0;
  regs.p.h = 0;
}

void op_cmc() {
  idle();
  idle();
  regs.p.c = !regs.p.c;
}

void op_daa() {
  idle();
  idle();
  if(regs.p.c || (regs.a) > 0x99) {
    regs.a += 0x60;
    regs.p.c = 1;
  }
  if(regs.p.h || (regs.a & 15) > 0x09) {
    regs.a += 0x06;
  }
  regs.p.n = (regs.a & 0x80) != 0;
  regs.p.z = (regs.a == 0);
}

void op_das() {
  idle();
  idle();
  if(!regs.p.c || (regs.a) > 0x99) {
    regs.a -= 0x60;
    regs.p.c = 0;
  }
  if(!regs.p.h || (regs.a & 15) > 0x09) {
    regs.a -= 0x06;
  }
  regs.p.n = (regs.a & 0x80) != 0;
  regs.p.z = (regs.a == 0);
}

void op_div_ya_x() {
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
  idle();
  ya = regs.ya;
  //overflow set if quotient >= 256
  regs.p.v = (regs.y >= regs.x);
  regs.p.h = ((regs.y & 15) >= (regs.x & 15));
  if(regs.y < (regs.x << 1)) {
    //if quotient is <= 511 (will fit into 9-bit result)
    regs.a = cast(ubyte) (ya / regs.x);
    regs.y = ya % regs.x;
  } else {
    //otherwise, the quotient won't fit into regs.p.v + regs.a
    //this emulates the odd behavior of the S-SMP in this case
    regs.a = cast(ubyte) (255    - (ya - (regs.x << 9)) / (256 - regs.x));
    regs.y = cast(ubyte) (regs.x + (ya - (regs.x << 9)) % (256 - regs.x));
  }
  //result is set based on a (quotient) only
  regs.p.n = (regs.a & 0x80) != 0;
  regs.p.z = (regs.a == 0);
}

void op_jmp_addr() {
  rd.l = readPC();
  rd.h = readPC();
  regs.pc = rd;
}

void op_jmp_iaddrx() {
  dp.l = readPC();
  dp.h = readPC();
  idle();
  dp += regs.x;
  rd.l = read(dp++);
  rd.h = read(dp++);
  regs.pc = rd;
}

void op_jsp_dp() {
  rd = readPC();
  idle();
  idle();
  writeSP(regs.pc.h);
  writeSP(regs.pc.l);
  regs.pc = 0xff00 | rd;
}

void op_jsr_addr() {
  rd.l = readPC();
  rd.h = readPC();
  idle();
  idle();
  idle();
  writeSP(regs.pc.h);
  writeSP(regs.pc.l);
  regs.pc = rd;
}

void op_jst() {
  dp = 0xffde - ((opcode >> 4) << 1);
  rd.l = read(dp++);
  rd.h = read(dp++);
  idle();
  idle();
  idle();
  writeSP(regs.pc.h);
  writeSP(regs.pc.l);
  regs.pc = rd;
}

void op_lda_ixinc() {
  idle();
  regs.a = readDP(regs.x++);
  idle();
  regs.p.n = (regs.a & 0x80) != 0;
  regs.p.z = regs.a == 0;
}

void op_mul_ya() {
  idle();
  idle();
  idle();
  idle();
  idle();
  idle();
  idle();
  idle();
  ya = regs.y * regs.a;
  regs.a = cast(ubyte) ya;
  regs.y = ya >> 8;
  //result is set based on y (high-byte) only
  regs.p.n = (regs.y & 0x80) != 0;
  regs.p.z = (regs.y == 0);
}

void op_nop() {
  idle();
}

void op_plp() {
  idle();
  idle();
  regs.p = readSP();
}

void op_rti() {
  regs.p = readSP();
  rd.l = readSP();
  rd.h = readSP();
  idle();
  idle();
  regs.pc = rd;
}

void op_rts() {
  rd.l = readSP();
  rd.h = readSP();
  idle();
  idle();
  regs.pc = rd;
}

void op_sta_idpx() {
  sp = readPC() + regs.x;
  idle();
  dp.l = readDP(cast(ubyte) sp++);
  dp.h = readDP(cast(ubyte) sp++);
  read(dp);
  write(dp, regs.a);
}

void op_sta_idpy() {
  sp = readPC();
  dp.l = readDP(cast(ubyte) sp++);
  dp.h = readDP(cast(ubyte) sp++);
  idle();
  dp += regs.y;
  read(dp);
  write(dp, regs.a);
}

void op_sta_ix() {
  idle();
  readDP(regs.x);
  writeDP(regs.x, regs.a);
}

void op_sta_ixinc() {
  idle();
  idle();
  writeDP(regs.x++, regs.a);
}

void op_stw_dp() {
  dp = readPC();
  readDP(cast(ubyte) dp);
  writeDP(cast(ubyte) dp++, regs.a);
  writeDP(cast(ubyte) dp++, regs.y);
}

void op_wait() {
  while(true) {
    idle();
    idle();
  }
}

void op_xcn() {
  idle();
  idle();
  idle();
  idle();
  regs.a = cast(ubyte) ((regs.a >> 4) | (regs.a << 4));
  regs.p.n = (regs.a & 0x80) != 0;
  regs.p.z = regs.a == 0;
}

// SPC700 Opcode Table
// -------------------------------------------------------------------------------------------------

void instruction() {
  switch (opcode = readPC()) {
  default: assert(0);
  case 0x00: return op_nop();
  case 0x01: return op_jst();
  case 0x02: return op_set_bit();
  case 0x03: return op_branch_bit();
  // case 0x04: return op_read_dp!(op_or, regs.a);
  // case 0x05: return op_read_addr!or(regs.a);
  // case 0x06: return op_read_ix!or();
  // case 0x07: return op_read_idpx!or();
  // case 0x08: return op_read_const!or(regs.a);
  // case 0x09: return op_writ_dp_dp!or();
  // case 0x0a: return op_set_addr_bit();
  // case 0x0b: return op_adjust_dp!asl();
  // case 0x0c: return op_adjust_addr!asl();
  // case 0x0d: return op_push(regs.p);
  // case 0x0e: return op_test_addr(1);
  // case 0x0f: return op_brk();
  // case 0x10: return op_branch(regs.p.n == 0);
  // case 0x11: return op_jst();
  // case 0x12: return op_set_bit();
  // case 0x13: return op_branch_bit();
  // case 0x14: return op_read_dpi!or(regs.a, regs.x);
  // case 0x15: return op_read_addri!or(regs.x);
  // case 0x16: return op_read_addri!or(regs.y);
  // case 0x17: return op_read_idpy!or();
  // case 0x18: return op_write_dp_const!or();
  // case 0x19: return op_write_ix_iy!or();
  // case 0x1a: return op_adjust_dpw(-1);
  // case 0x1b: return op_adjust_dpx!asl();
  // case 0x1c: return op_adjust!asl(regs.a);
  // case 0x1d: return op_adjust!dec(regs.x);
  // case 0x1e: return op_read_addr!cmp(regs.x);
  // case 0x1f: return op_jmp_iaddrx();
  // case 0x20: return op_set_flag(regs.p.p.bit, 0);
  // case 0x21: return op_jst();
  // case 0x22: return op_set_bit();
  // case 0x23: return op_branch_bit();
  // case 0x24: return op_read_dp!and(regs.a);
  // case 0x25: return op_read_addr!and(regs.a);
  // case 0x26: return op_read_ix!and();
  // case 0x27: return op_read_idpx!and();
  // case 0x28: return op_read_const!and(regs.a);
  // case 0x29: return op_write_dp!and();
  // case 0x2a: return op_set_addr_bit();
  // case 0x2b: return op_adjust_dp!rol();
  // case 0x2c: return op_adjust_addr!rol();
  // case 0x2d: return op_push(regs.a);
  // case 0x2e: return op_bne_dp();
  // case 0x2f: return op_branch(true);
  // case 0x30: return op_branch(regs.p.n == 1);
  // case 0x31: return op_jst();
  // case 0x32: return op_set_bit();
  // case 0x33: return op_branch_bit();
  // case 0x34: return op_read_dpi!and(regs.a, regs.x);
  // case 0x35: return op_read_addri!and(regs.x);
  // case 0x36: return op_read_addri!and(regs.y);
  // case 0x37: return op_read_idpy!and();
  // case 0x38: return op_write_dp_const!and();
  // case 0x39: return op_write_ix_iy!and();
  // case 0x3a: return op_adjust_dpw(1);
  // case 0x3b: return op_adjust_dpx!rol();
  // case 0x3c: return op_adjust!rol(regs.a);
  // case 0x3d: return op_adjust!inc(regs.x);
  // case 0x3e: return op_read_dp!cmp(regs.x);
  // case 0x3f: return op_jsr_addr();
  // case 0x40: return op_set_flag(regs.p.p.bit, 1);
  // case 0x41: return op_jst();
  // case 0x42: return op_set_bit();
  // case 0x43: return op_branch_bit();
  // case 0x44: return op_read_dp!eor(regs.a);
  // case 0x45: return op_read_addr!eor(regs.a);
  // case 0x46: return op_read_ix!eor();
  // case 0x47: return op_read_idpx!eor();
  // case 0x48: return op_read_const!eor(regs.a);
  // case 0x49: return op_write_dp_dp!eor();
  // case 0x4a: return op_set_addr_bit();
  // case 0x4b: return op_adjust_dp!lsr();
  // case 0x4c: return op_adjust_addr!lsr();
  // case 0x4d: return op_push(regs.x);
  // case 0x4e: return op_test_addr(0);
  // case 0x4f: return op_jsp_dp();
  // case 0x50: return op_branch(regs.p.v == 0);
  // case 0x51: return op_jst();
  // case 0x52: return op_set_bit();
  // case 0x53: return op_branch_bit();
  // case 0x54: return op_read_dpi!eor(regs.a, regs.x);
  // case 0x55: return op_read_addri!eor(regs.x);
  // case 0x56: return op_read_addri!eor(regs.y);
  // case 0x57: return op_read_idpy!eor();
  // case 0x58: return op_write_dp_const!eor();
  // case 0x59: return op_write_ix_iy!eor();
  // case 0x5a: return op_read_dpw!cpw();
  // case 0x5b: return op_adjust_dpx!lsr();
  // case 0x5c: return op_adjust!lsr(regs.a);
  // case 0x5d: return op_transfer(regs.a, regs.x);
  // case 0x5e: return op_read_addr!cmp(regs.y);
  // case 0x5f: return op_jmp_addr();
  // case 0x60: return op_set_flag(regs.p.c.bit, 0);
  // case 0x61: return op_jst();
  // case 0x62: return op_set_bit);
  // case 0x63: return op_branch_bit);
  // case 0x64: return op_read_dp, fp(cmp), regs.a);
  // case 0x65: return op_read_addr, fp(cmp), regs.a);
  // case 0x66: return op_read_ix, fp(cmp));
  // case 0x67: return op_read_idpx, fp(cmp));
  // case 0x68: return op_read_const, fp(cmp), regs.a);
  // case 0x69: return op_write_dp_dp, fp(cmp));
  // case 0x6a: return op_set_addr_bit);
  // case 0x6b: return op_adjust_dp, fp(ror));
  // case 0x6c: return op_adjust_addr, fp(ror));
  // case 0x6d: return op_push, regs.y);
  // case 0x6e: return op_bne_dpdec);
  // case 0x6f: return op_rts();
  // case 0x70: return op_branch(regs.p.v == 1);
  // case 0x71: return op_jst();
  // case 0x72: return op_set_bit);
  // case 0x73: return op_branch_bit);
  // case 0x74: return op_read_dpi, fp(cmp), regs.a, regs.x);
  // case 0x75: return op_read_addri, fp(cmp), regs.x);
  // case 0x76: return op_read_addri, fp(cmp), regs.y);
  // case 0x77: return op_read_idpy, fp(cmp));
  // case 0x78: return op_write_dp_const, fp(cmp));
  // case 0x79: return op_write_ix_iy, fp(cmp));
  // case 0x7a: return op_read_dpw, fp(adw));
  // case 0x7b: return op_adjust_dpx, fp(ror));
  // case 0x7c: return op_adjust, fp(ror), regs.a);
  // case 0x7d: return op_transfer(regs.x, regs.a);
  // case 0x7e: return op_read_dp, fp(cmp), regs.y);
  // case 0x7f: return op_rti();
  // case 0x80: return op_set_flag, regs.p.c.bit, 1);
  // case 0x81: return op_jst();
  // case 0x82: return op_set_bit);
  // case 0x83: return op_branch_bit);
  // case 0x84: return op_read_dp, fp(adc), regs.a);
  // case 0x85: return op_read_addr, fp(adc), regs.a);
  // case 0x86: return op_read_ix, fp(adc));
  // case 0x87: return op_read_idpx, fp(adc));
  // case 0x88: return op_read_const, fp(adc), regs.a);
  // case 0x89: return op_write_dp_dp, fp(adc));
  // case 0x8a: return op_set_addr_bit);
  // case 0x8b: return op_adjust_dp, fp(dec));
  // case 0x8c: return op_adjust_addr, fp(dec));
  // case 0x8d: return op_read_const, fp(ld), regs.y);
  // case 0x8e: return op_plp();
  // case 0x8f: return op_write_dp_const, fp(st));
  // case 0x90: return op_branch(regs.p.c == 0);
  // case 0x91: return op_jst();
  // case 0x92: return op_set_bit);
  // case 0x93: return op_branch_bit);
  // case 0x94: return op_read_dpi, fp(adc), regs.a, regs.x);
  // case 0x95: return op_read_addri, fp(adc), regs.x);
  // case 0x96: return op_read_addri, fp(adc), regs.y);
  // case 0x97: return op_read_idpy, fp(adc));
  // case 0x98: return op_write_dp_const, fp(adc));
  // case 0x99: return op_write_ix_iy, fp(adc));
  // case 0x9a: return op_read_dpw, fp(sbw));
  // case 0x9b: return op_adjust_dpx, fp(dec));
  // case 0x9c: return op_adjust(, fp(dec), regs.a);
  // case 0x9d: return op_transfer(regs.s, regs.x);
  // case 0x9e: return op_div_ya_x);
  // case 0x9f: return op_xcn();
  // case 0xa0: return op_set_flag, regs.p.i.bit, 1);
  // case 0xa1: return op_jst();
  // case 0xa2: return op_set_bit);
  // case 0xa3: return op_branch_bit);
  // case 0xa4: return op_read_dp, fp(sbc), regs.a);
  // case 0xa5: return op_read_addr, fp(sbc), regs.a);
  // case 0xa6: return op_read_ix, fp(sbc));
  // case 0xa7: return op_read_idpx, fp(sbc));
  // case 0xa8: return op_read_const, fp(sbc), regs.a);
  // case 0xa9: return op_write_dp_dp, fp(sbc));
  // case 0xaa: return op_set_addr_bit);
  // case 0xab: return op_adjust_dp, fp(inc));
  // case 0xac: return op_adjust_addr, fp(inc));
  // case 0xad: return op_read_const, fp(cmp), regs.y);
  // case 0xae: return op_pull(regs.a);
  // case 0xaf: return op_sta_ixinc);
  // case 0xb0: return op_branch(regs.p.c == 1);
  // case 0xb1: return op_jst();
  // case 0xb2: return op_set_bit);
  // case 0xb3: return op_branch_bit);
  // case 0xb4: return op_read_dpi, fp(sbc), regs.a, regs.x);
  // case 0xb5: return op_read_addri, fp(sbc), regs.x);
  // case 0xb6: return op_read_addri, fp(sbc), regs.y);
  // case 0xb7: return op_read_idpy, fp(sbc));
  // case 0xb8: return op_write_dp_const, fp(sbc));
  // case 0xb9: return op_write_ix_iy, fp(sbc));
  // case 0xba: return op_read_dpw, fp(ldw));
  // case 0xbb: return op_adjust_dpx, fp(inc));
  // case 0xbc: return op_adjust(, fp(inc), regs.a);
  // case 0xbd: return op_transfer(regs.x, regs.s);
  // case 0xbe: return op_das();
  // case 0xbf: return op_lda_ixinc);
  // case 0xc0: return op_set_flag, regs.p.i.bit, 0);
  // case 0xc1: return op_jst();
  // case 0xc2: return op_set_bit);
  // case 0xc3: return op_branch_bit);
  // case 0xc4: return op_write_dp, regs.a);
  // case 0xc5: return op_write_addr, regs.a);
  // case 0xc6: return op_sta_ix);
  // case 0xc7: return op_sta_idpx);
  // case 0xc8: return op_read_const, fp(cmp), regs.x);
  // case 0xc9: return op_write_addr, regs.x);
  // case 0xca: return op_set_addr_bit);
  // case 0xcb: return op_write_dp, regs.y);
  // case 0xcc: return op_write_addr, regs.y);
  // case 0xcd: return op_read_const, fp(ld), regs.x);
  // case 0xce: return op_pull(regs.x);
  // case 0xcf: return op_mul_ya);
  // case 0xd0: return op_branch(regs.p.z == 0);
  // case 0xd1: return op_jst();
  // case 0xd2: return op_set_bit);
  // case 0xd3: return op_branch_bit);
  // case 0xd4: return op_write_dpi, regs.a, regs.x);
  // case 0xd5: return op_write_addri, regs.x);
  // case 0xd6: return op_write_addri, regs.y);
  // case 0xd7: return op_sta_idpy);
  // case 0xd8: return op_write_dp, regs.x);
  // case 0xd9: return op_write_dpi, regs.x, regs.y);
  // case 0xda: return op_stw_dp);
  // case 0xdb: return op_write_dpi, regs.y, regs.x);
  // case 0xdc: return op_adjust(fp(dec), regs.y);
  // case 0xdd: return op_transfer(regs.y, regs.a);
  // case 0xde: return op_bne_dpx);
  // case 0xdf: return op_daa();
  // case 0xe0: return op_clv();
  // case 0xe1: return op_jst();
  // case 0xe2: return op_set_bit);
  // case 0xe3: return op_branch_bit);
  // case 0xe4: return op_read_dp, fp(ld), regs.a);
  // case 0xe5: return op_read_addr, fp(ld), regs.a);
  // case 0xe6: return op_read_ix, fp(ld));
  // case 0xe7: return op_read_idpx, fp(ld));
  // case 0xe8: return op_read_const, fp(ld), regs.a);
  // case 0xe9: return op_read_addr, fp(ld), regs.x);
  // case 0xea: return op_set_addr_bit);
  // case 0xeb: return op_read_dp, fp(ld), regs.y);
  // case 0xec: return op_read_addr, fp(ld), regs.y);
  // case 0xed: return op_cmc();
  // case 0xee: return op_pull(regs.y);
  // case 0xef: return op_wait();
  // case 0xf0: return op_branch(regs.p.z == 1);
  // case 0xf1: return op_jst();
  // case 0xf2: return op_set_bit);
  // case 0xf3: return op_branch_bit);
  // case 0xf4: return op_read_dpi, fp(ld), regs.a, regs.x);
  // case 0xf5: return op_read_addri, fp(ld), regs.x);
  // case 0xf6: return op_read_addri, fp(ld), regs.y);
  // case 0xf7: return op_read_idpy, fp(ld));
  // case 0xf8: return op_read_dp, fp(ld), regs.x);
  // case 0xf9: return op_read_dpi, fp(ld), regs.x, regs.y);
  // case 0xfa: return op_write_dp_dp, fp(st));
  // case 0xfb: return op_read_dpi, fp(ld), regs.y, regs.x);
  // case 0xfc: return op_adjust(, fp(inc), regs.y);
  // case 0xfd: return op_transfer(regs.a, regs.y);
  // case 0xfe: return op_bne_ydec);
  // case 0xff: return op_wait();
  }
}
