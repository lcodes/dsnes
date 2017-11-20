/**
 * Emulator application entry point.
 */
module emulator.system;

import std.exception : enforce;
import std.string    : toStringz;

import derelict.sdl2.sdl;

import nfd;

import emulator.util : sdlCheck, sdlRaise;

import console = emulator.console;
import script  = emulator.script;
import thread  = emulator.thread;

import audio = emulator.audio;
import imgui = emulator.gui;
import input = emulator.input;
import video = emulator.video;

import gui = gui.system;

// State
// -------------------------------------------------------------------------------------------------

private __gshared {
  System[] systems;
  System sys;

  string fileName;
  uint quickSlot;

  Colorburst _colorburst;
}

__gshared {
  bool hideAlerts;
}

nothrow @nogc {
  System current() {
    return sys;
  }

  string file() {
    return fileName;
  }
  void file(string value) {
    assert(!isPowered);
    fileName = value;
  }

  Colorburst colorburst() {
    return _colorburst;
  }
}

enum Colorburst : double {
  NTSC = 315.0 / 88.0 * 1_000_000.0,
  PAL  = 283.75 * 15_625.0 + 25.0
}

// Core
// -------------------------------------------------------------------------------------------------

alias isRunning = thread.isRunning;
alias isPowered = thread.isPowered;
alias quit      = thread.quit;

void fatal(Throwable e, bool rethrow = true) {
  int result;

  if (!hideAlerts) {
    result = SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "Error!",
                                      e.msg.toStringz, video.sdlWindow);
  }

  if (rethrow) {
    result.sdlCheck;
    throw e;
  }
}

void run() {
  initialize();
  scope (exit)    terminate();
  scope (failure) thread.quit();

  console.trace("DEMU Ready");

  if (file !is null) {
    file.open();
  }

  console.trace("Running DEMU");

  try while (thread.isRunning) {
    event.run();
    input.run();
    audio.run();
    video.run();
    imgui.run();
    video.end();
    timer.run();
  }
  catch (Exception e) {
    e.fatal();
  }
}

private:

void initialize() {
  assert(!DerelictSDL2.isLoaded);
  assert(!thread.isRunning);
  console.trace("Starting DEMU");

  DerelictSDL2.load();

  try {
    if (SDL_Init(SDL_INIT_AUDIO | SDL_INIT_VIDEO) < 0) {
      sdlRaise();
    }

    console.initialize();
    script.initialize();
    thread.initialize();

    input.initialize();
    audio.initialize();
    video.initialize();
    imgui.initialize();

    gui.initialize();
  }
  catch (Exception e) {
    e.fatal();
  }
}

void terminate() {
  assert(!thread.isRunning);
  console.trace("Stopping DEMU");

  if (!DerelictSDL2.isLoaded) return;

  terminate!gui();

  terminate!imgui();
  terminate!video();
  terminate!audio();
  terminate!input();

  terminate!thread();
  terminate!script();
  terminate!console();

  SDL_Quit();
  DerelictSDL2.unload();
}

void terminate(alias m)() {
  try m.terminate();
  catch (Exception e) e.fatal(false);
}

// Files
// -------------------------------------------------------------------------------------------------

public:

void open() {
  nfdchar_t* outPath;
  switch (NFD_OpenDialog(null, null, &outPath)) {
  case NFD_OKAY:
    scope (exit) outPath.free();
    outPath.to!string.open();
    break;

  case NFD_CANCEL: break;
  default:         throw new Exception(NFD_GetError().to!string);
  }
}

void open(string path) {
  thread.power(false);

  file = path;

  try {
   sys.load(path);
   sys.power();

   thread.power(true);
  }
  catch (Exception e) {
    console.error(e.msg);
    e.fatal(false);
  }
}

uint numRecentFiles() {
  return 0;
}

void openRecent(uint n) {
  
}

void clearRecentFiles() {
  
}

// Save States
// -------------------------------------------------------------------------------------------------

uint quickStateSlot() {
  return quickSlot;
}
void quickStateSlot(uint index) {
  enforce(index < 10);
  quickSlot = index;
}

void quickSaveState() {
  quickSlot.saveState();
}
void quickLoadState() {
  quickSlot.loadState();
}

void saveState(uint slot) {
  enforce(slot < 10);

}

void loadState(uint slot) {
  enforce(slot < 10);

}

// Platforms
// -------------------------------------------------------------------------------------------------

interface System {
  static struct Information {
    string manufacturer;
    string name;
    bool overscan;
  }

  static struct Device {
    string name;
    Input[] inputs;

    static struct Input {
      string name;
    }
  }

  static struct Port {
    string name;
    Device[] devices;
  }

  string title();

  static struct VideoSize {
    uint width, height;
  }

  VideoSize videoSize();
  VideoSize videoSize(uint width, uint height, bool arc);
  uint videoColors();
  ulong videoColor(uint color);

  bool loaded();
  void load(string file);
  void save();
  void unload();

  void connect(uint port, uint device);
  void power();
  void run();

  bool rtc();
  void rtcSync();

  // void serialize();
  // void deserialize();

  // void setCheat();

  // bool cap();
  // Variant get(string name);
  // void set(string name, Variant value);

  // uint videoColor(ushort r, ushort g, ushort b);

  final System register() {
    sys = this; // TODO: remove
    systems ~= this;
    return this;
  }
}

// Internals
// -------------------------------------------------------------------------------------------------

package:

void threadRun() {
  sys.run();
}

private:

struct event { @disable this();
  static void run() {
    SDL_Event event = void;
    SDL_PollEvent(&event);

    imgui.processEvent(&event);

    switch (event.type) {
    default: break;
    case SDL_QUIT: thread.quit(); break;

    case SDL_WINDOWEVENT:
      switch (event.window.event) {
      default: break;

      case SDL_WINDOWEVENT_SHOWN: break;
      case SDL_WINDOWEVENT_HIDDEN: break;
      case SDL_WINDOWEVENT_EXPOSED: break;
      case SDL_WINDOWEVENT_MOVED:   video.onMove  (event.window.data1, event.window.data2); break;
      case SDL_WINDOWEVENT_RESIZED: video.onResize(event.window.data1, event.window.data2); break;
      case SDL_WINDOWEVENT_SIZE_CHANGED: break;
      case SDL_WINDOWEVENT_MINIMIZED: break;
      case SDL_WINDOWEVENT_MAXIMIZED: break;
      case SDL_WINDOWEVENT_RESTORED: break;
      case SDL_WINDOWEVENT_ENTER: break;
      case SDL_WINDOWEVENT_LEAVE: break;
      case SDL_WINDOWEVENT_FOCUS_GAINED: break;
      case SDL_WINDOWEVENT_FOCUS_LOST: break;
      case SDL_WINDOWEVENT_CLOSE: break;
      case SDL_WINDOWEVENT_TAKE_FOCUS: break;
      case SDL_WINDOWEVENT_HIT_TEST: break;
      }
      break;

    case SDL_AUDIODEVICEADDED: break;
    case SDL_AUDIODEVICEREMOVED: break;

    case SDL_CONTROLLERDEVICEADDED: break;
    case SDL_CONTROLLERDEVICEREMOVED: break;
    case SDL_CONTROLLERDEVICEREMAPPED: break;

    case SDL_KEYDOWN: break;
    case SDL_KEYUP: break;

    case SDL_TEXTEDITING: break;
    case SDL_TEXTINPUT:   break;

    case SDL_MOUSEMOTION: break;
    case SDL_MOUSEBUTTONDOWN: break;
    case SDL_MOUSEBUTTONUP: break;
    case SDL_MOUSEWHEEL: break;

    case SDL_JOYAXISMOTION: break;
    case SDL_JOYBALLMOTION: break;
    case SDL_JOYHATMOTION: break;

    case SDL_CONTROLLERAXISMOTION: break;
    case SDL_CONTROLLERBUTTONDOWN: break;
    case SDL_CONTROLLERBUTTONUP: break;

    case SDL_FINGERMOTION:
    case SDL_FINGERDOWN:
    case SDL_FINGERUP: break;

    case SDL_MULTIGESTURE: break;
    case SDL_DOLLARGESTURE: break;
    case SDL_DOLLARRECORD: break;

    case SDL_DROPFILE:
    case SDL_DROPTEXT:
    case SDL_DROPBEGIN:
    case SDL_DROPCOMPLETE: break;
    }
  }
}

struct timer { @disable this();
  static void run() {
    // SDL_Delay(10); // TODO: 
  }
}
