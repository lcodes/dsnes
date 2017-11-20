module gui.system;

import gui.files;
// import gui.game;

// import gui.breakpoints;
// import gui.console;
import gui.debugger;
// import gui.profiler;

import gui.cpu;
// import gui.ppu;
// import gui.smp;

// import gui.inputs;
// import gui.memory;
// import gui.registers;

import menu   = gui.menu;
import status = gui.status;

// import snes.memory;

__gshared ubyte[0x20000] sram;

ubyte r(uint a) { return sram[a]; }
void w(uint a, ubyte b) { sram[a] = b; }

void initialize() {
  new FilesWindow();
  // new GameWindow();

  // new BreakpointsWindow();
  // new ConsoleWindow();
  new DebuggerWindow();
  // new ProfilerWindow();

  new CpuWindow();
  // new PpuWindow();
  // new SmpWindow();

  // new InputsWindow();
  // new RegistersWindow();
  // new MemoryWindow(0x20000, &r, &w);
}

void terminate() {

}

void draw() {
  menu.draw();
  status.draw();
}
