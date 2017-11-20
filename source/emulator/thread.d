module emulator.thread;

import core.atomic : atomicLoad, atomicStore;
import core.thread : Fiber, Thread;

import core.sync.semaphore : Semaphore;

import std.conv : to;

import emulator.util : cstring;

import console = emulator.console;
import system  = emulator.system;

debug {
  import core.stdc.stdio : printf;

  // debug = Thread;
  // debug = Thread_Call;
  // debug = Thread_Sync;
}

// State
// -------------------------------------------------------------------------------------------------

private __gshared {
  Proc[]    processors;
  Fiber     main, park, cont, next;
  Thread    emulatorThread;
  Semaphore powerSync;
  Semaphore breakpoint;

  Mode  mode;
  Event lastEvent;

  shared bool powerOn;
  shared bool running;
  shared bool paused;
  shared bool breakpointRequested;
}

enum second = ulong.max >> 1;

enum Event : ubyte {
  step,
  frame,
  synchronize
}

enum Mode : ubyte {
  run,
  synchronizeMaster,
  synchronizeSlave
}

struct Proc {
  Fiber fiber;
  ulong clock;
  ulong scalar;

  private ulong _frequency;

  debug cstring name;

  nothrow @nogc:

  void primary() { main = park = fiber; }

  ulong frequency() { return _frequency; }
  void frequency(double value) {
    _frequency = cast(ulong) (value + 0.5);

    scalar = cast(ulong) (second / _frequency);
  }

  void step(uint clocks) { clock += scalar * clocks; }

  void synchronize(Proc* proc) {
    assert(proc !is null && proc.fiber !is null);
    assert(proc.fiber.state == Fiber.State.HOLD);
    debug (Thread_Sync) printf("thread.Proc.synchronize from=%s proc=%s\n", fiberName, proc.name);
    if (clock >= proc.clock) (cast(void function(Proc*) nothrow @nogc) &resume)(proc);
  }
}

alias Processor = Proc*;

// Core
// -------------------------------------------------------------------------------------------------

nothrow @nogc {
  bool synchronizing() { return mode == Mode.synchronizeSlave; }

  bool isPowered() { return powerOn.atomicLoad; }
  bool isRunning() { return running.atomicLoad; }
  bool isPaused() { return paused.atomicLoad; }
}

Proc* create(string mod = __MODULE__)(void function() entry, double frequency) {
  assert(entry !is null);
  debug (Thread) printf("thread.create %s frequency=%f\n", mod.ptr, frequency);
  processors ~= Proc(new Fiber(entry, 64 * 1024 * size_t.sizeof));

  auto proc = &processors[$ - 1];
  proc.frequency = frequency.to!ulong;
  proc.clock += processors.length; // This bias prioritizes processors appended earlier first.
  debug proc.name = mod.ptr;

  if (processors.length == 1) main = cont = proc.fiber;
  return proc;
}

void power(bool value) {
  if (isPowered == value) return;
  debug (Thread) printf("thread.power %u\n", value);
  powerOn.atomicStore = value;
  powerSync.notify();
}

void reset() nothrow @nogc {
  debug (Thread) printf("thread.reset\n");
  park = Fiber.getThis;
  processors = null;
}

Event run(Mode m = Mode.run) {
  debug (Thread) printf("thread.run %u from=%s cont=%s\n", m, fiberName, cont.fiberName);
  assert(cont !is null);
  assert(cont.state == Fiber.State.HOLD);
  mode = m;
  park = Fiber.getThis;

  if (breakpointRequested) {
    breakpointRequested = false;
    brk();
  }

  next = cont;
  Fiber.yield();
  return lastEvent;
}

void quit() {
  debug (Thread) printf("thread.quit\n");
  powerOn.atomicStore = false;
  running.atomicStore = false;

  breakpoint.notify();
  powerSync .notify();
}

void synchronize(Proc* proc) {
  assert(proc !is null && proc.fiber !is null);
  assert(proc.fiber.state == Fiber.State.HOLD);
  debug (Thread_Sync) printf("thread.synchronize from=%s proc=%s\n", fiberName, proc.name);
  if (proc.fiber is main) {
    while (run(Mode.synchronizeMaster) != Event.synchronize) {}
  }
  else {
    cont = proc.fiber;
    while (run(Mode.synchronizeSlave) != Event.synchronize) {}
  }
}

void synchronize() {
  debug (Thread_Sync) printf("thread.synchronize from=%s\n", fiberName);
  if (Fiber.getThis is main) {
    if (mode == Mode.synchronizeMaster) yield(Event.synchronize);
  }
  else {
    if (mode == Mode.synchronizeSlave) yield(Event.synchronize);
  }
}

void brk() nothrow @nogc { (cast(void function() nothrow @nogc) &_brk)(); }
void _brk() {
  if (isPowered) {
    paused.atomicStore = true;
    breakpoint.wait();
    paused.atomicStore = false;
  }
}

void dbgBreak() {
  breakpointRequested.atomicStore = true;
}

void dbgContinue() {
  breakpoint.notify();
}

package void initialize() {
  assert(emulatorThread is null);

  console.trace("Initialize");
  running.atomicStore = true;

  powerSync  = new Semaphore();
  breakpoint = new Semaphore();

  emulatorThread = new Thread(&entry);
  emulatorThread.start();
}

package void terminate() {
  assert(!isPowered);
  assert(!isRunning);
  console.trace("Terminate");

  breakpoint.notify();
  powerSync .notify();

  emulatorThread.join();
  emulatorThread = null;

  breakpoint = null;
  powerSync  = null;

  reset();
}

// Emulation thread.
// -------------------------------------------------------------------------------------------------

void yield(Event e) nothrow @nogc {
  debug (Thread) printf("thread.yield %s event=%u\n", fiberName, e);

  auto minimum = ulong.max;
  foreach (p; processors) if (p.clock < minimum) minimum = p.clock;
  foreach (p; processors) p.clock -= minimum;

  lastEvent = e;
  cont = Fiber.getThis;
  next = park;
  Fiber.yield();
}

private:

void resume(Proc* proc) {
  assert(proc !is null && proc.fiber !is null);
  assert(proc.fiber.state == Fiber.State.HOLD);

  if (mode != Mode.synchronizeSlave) {
    debug (Thread) printf("thread.resume %s\n", proc.name);
    next = proc.fiber;
    Fiber.yield();
  }
}

void entry() {
  scope (failure) quit();
  console.trace("Emulator thread started");

  auto core = next = new Fiber(&system.threadRun, 0x1000);

  while (isRunning) { // Loops once per power on/off cycle.
    powerSync.wait();

    console.trace("Emulator thread power on");

    while (isPowered) {
      debug (Thread_Call) printf("thread.entry %s\n", next.fiberName);
      assert(next.state == Fiber.State.HOLD);
      next.call();
    }

    console.trace("Emulator thread power off");
  }
}

nothrow @nogc:

debug cstring fiberName(Fiber f = Fiber.getThis) {
  if (f is null) return "<none>";
  foreach (p; processors) if (p.fiber is f) return p.name;
  return "<ctrl>";
}
