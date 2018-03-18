/**
 * Emulator system. Binds the application together.
 */
module emulator.system;

import std = core.stdc.stdlib;

import core.atomic : MemoryOrder, atomicLoad, atomicStore;
import core.time   : MonoTime, dur;
import core.thread : thread_isMainThread;

import std.array     : empty, join, split;
import std.exception : enforce;
import std.path      : extension;
import std.stdio     : stderr;
import std.string    : toStringz;

import derelict.glfw3.glfw3;

// static import messagebox;
import nfd;

import host = emulator.platform;
import user = emulator.user;
import util = emulator.util;

import console = emulator.console;

import script = emulator.script;
import thread = emulator.thread;
import worker = emulator.worker;

import audio = emulator.audio;
import imgui = emulator.gui;
import input = emulator.input;
import perfs = emulator.profiler : Profile;
import video = emulator.video;

static assert(is(nfdchar_t == char), "Expecting NFD to use UTF-8 characters.");

// State
// -----------------------------------------------------------------------------

private __gshared {
  Settings _settings; /// Global application settings. User configurable.

  System[] systems; /// Emulated systems. Determines file support.
  System _current;  /// Currently active system. Non-null when a file is loaded.

  Colorburst _colorburst;

  string fileName; /// Path of the currently opened cartridge.

  const(nfdchar_t)* openFilters; /// Generated file filters for the open dialog.
  const(nfdchar_t)* openPath;    /// Last path used with the open dialog.
}

struct Settings {
  bool   openLastFileOnStart = true;
  ushort maxRecentFiles      = 10;
}

__gshared {
  Exception lastException;
  bool hideAlerts;
}

nothrow @nogc {
  System current() {
    return _current;
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

  bool isExtensionSupported(string ext) {
    if (ext[0] == '.') {
      ext = ext[1..$];
    }

    return ext in loader.systemsByFileExtension ||
           ext in loader.unpacksByFileExtension;
  }
}

enum Colorburst : double {
  NTSC = 315.0 / 88.0 * 1_000_000.0,
  PAL  = 283.75 * 15_625.0 + 25.0
}

/// Display a fatal error.
void fatal(string message) {
  stderr.writeln(message);

  // messagebox.dialog(null, "Fatal Error", message,
  //                   messagebox.Buttons.Ok | messagebox.Icon.Error);

  std.exit(std.EXIT_FAILURE);
}

void fatal(Throwable e, bool rethrow = true) {
  if (rethrow) {
    console.fatal(e.msg);
    throw e;
  }
  else {
    fatal(e.msg);
  }
}

// Lifecycle
// -----------------------------------------------------------------------------

alias isRunning = thread.isRunning;
alias isPowered = thread.isPowered;

/// Thrown to exit the application with a specific error code.
class Quit : Exception {
  const int exitCode;
  this(int exitCode = 0) {
    super(null);
    this.exitCode = exitCode;
  }
}

/// Stops the application. Throws a Quit exception if an exit code is given.
void quit() {
  thread.quit();
  video .quit();
}
/// ditto
void quit(int exitCode) {
  quit();

  throw new Quit(exitCode);
}

/// Main execution loop.
void run() {
  initialize();
  scope (exit) terminate();

  console.info("Ready");

  firstFrame();

  console.trace("Running");

  while (thread.isRunning) {
    try {
      scope auto p = new Profile!();

      perfs.run();
      event.run();
      audio.run();
      video.run();
      imgui.run();
      video.end();
      timer.end();
      event.end();
      perfs.end();
    }
    catch (Quit e) {
      throw e;
    }
    catch (Exception e) {
      lastException = e;
      console.error(e);
    }
  }
}

private:

/// Performs first-frame initialization.
void firstFrame() {
  if (file !is null) {
    loader._open(file);
  }
}

/// Initializes all the application subsystems.
void initialize() {
  assert(!thread.isRunning);

  host.initialize();
  user.initialize();

  console.initialize();

  script.initialize();
  system.initialize();
  thread.initialize();
  worker.initialize();
  loader.initialize();
  recent.initialize();

  audio.initialize();
  video.initialize();
  imgui.initialize();
  input.initialize();
  perfs.initialize();
  state.initialize();
}

/// Terminates all the application subsystems.
void terminate() {
  quit();

  assert(!thread.isRunning);
  console.trace("Stopping");

  terminate!state();
  terminate!perfs();
  terminate!input();
  terminate!imgui();
  terminate!video();
  terminate!audio();

  terminate!recent();
  terminate!loader();
  terminate!worker();
  terminate!thread();
  terminate!system();
  terminate!script();

  terminate!console();

  terminate!user();
  terminate!host();
}

/// Terminates a single subsystem safely.
void terminate(alias m)() {
  try m.terminate();
  catch (Exception e) e.fatal(false);
}

// Emulated System
// -----------------------------------------------------------------------------

interface System {
  alias .current current;

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

  static struct VideoSize {
    uint width, height;
  }

  alias immutable string[] FileExts;

  const nothrow {
    string title();
    FileExts supportedExtensions();
    string loadRomInformation(string file);
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
    _current = this; // TODO: remove
    systems ~= this;
    return this;
  }
}

// Internals
// -----------------------------------------------------------------------------

package:

void threadRun() {
  _current.run();
}

private:

/**
 * Application system. Small wrapper over the GLFW library.
 */
struct system {
  mixin util.noCtors!();
  static:

  /// Loads the GLFW library and setup error its handling.
  void initialize() {
    assert(!DerelictGLFW3.isLoaded);
    DerelictGLFW3.load();

    glfwSetErrorCallback(&onGlfwError);
    enforce(glfwInit(), "GLFW init failed");

    int major = void, minor = void, patch = void;
    glfwGetVersion(&major, &minor, &patch);
    console.verbose("GLFW version ", major, ".", minor, ".", patch);
  }

  /// Unloads the GLFW library.
  void terminate() {
    if (!DerelictGLFW3.isLoaded) {
      glfwTerminate();
      DerelictGLFW3.unload();
    }
  }

  /// Called by GLFW each time a GLFW error occur.
  extern (C) void onGlfwError(int code, const(char)* msg) nothrow {
    console.fatal("GLFW error #", code, ": ", msg);
  }
}

/**
 * Event subsystem. Mostly delegated to GLFW.
 */
struct event {
  mixin util.noCtors!();
  static:

  __gshared {
    bool wait = true; /// Whether to block waiting on events instead of polling.
    byte tick;        /// Number of frames to run before waiting again.
  }

  shared {
    bool waiting; /// Whether the main thread is blocked waiting for input.
  }

  /**
   * Pumps events from the host windowing system. This triggers the registered
   * GLFW callbacks. These callbacks are defined in the input and video modules.
   */
  void run() nothrow @nogc {
    scope auto p = new Profile!();

    if (wait) {
      waiting.atomicStore!(MemoryOrder.raw)(true);

      if (tick) {
        glfwWaitEventsTimeout(cast(double) 1 / 120);
        tick--;
      }
      else {
        glfwWaitEvents();
        tick += 30; // Run freely for a few frames. This allows effects to run.
      }

      waiting.atomicStore!(MemoryOrder.raw)(false);
    }
    else {
      glfwPollEvents();
    }
  }

  // When the main window is being closed, the application should exit.
  void end() {
    scope auto p = new Profile!();

    if (video.window.glfwWindowShouldClose()) {
      quit(0);
    }
  }

  /// Sends an empty message to the main thread if blocked waiting on events.
  public void wakeMainThread() {
    assert(!thread_isMainThread());

    if (waiting.atomicLoad!(MemoryOrder.raw)()) {
      glfwPostEmptyEvent();
    }
  }
}

/**
 *
 */
struct timer {
static:
  mixin util.noCtors!();

  void end() nothrow @nogc {
    scope auto p = new Profile!();

  }
}

/**
 * Files loading. Handles I/O and compressions, delegates the rest to System.
 */
public struct loader {
static private:
  mixin util.noCtors!();

  alias Unpack = void function(string);

  static __gshared {
    Unpack[string] unpacksByFileExtension; /// Supported file compressions.
    System[string] systemsByFileExtension; /// Supported file formats.
  }

  /// Registers supported extensions.
  void initialize() {
    foreach (sys; systems) {
      foreach (ext; sys.supportedExtensions) {
        assert(ext !in systemsByFileExtension);
        systemsByFileExtension[ext] = sys;
      }
    }

    unpacksByFileExtension["gz"]     = &unpackGz;
    unpacksByFileExtension["tar"]    = &unpackTar;
    unpacksByFileExtension["tar.gz"] = &unpackTarGz;
    unpacksByFileExtension["zip"]    = &unpackZip;
  }

  // Unregisters all supported extensions.
  void terminate() {
    unpacksByFileExtension = null;
    systemsByFileExtension = null;
  }

  void unpackGz(string path) {
    auto ext = path[0..$-3].extension;
    enforce(ext, "Missing file extension before .gz");

    setSystemFromExt(ext[1..$]);

    // TODO:
  }

  void unpackTar(string path) {
    assert(0);
  }

  void unpackTarGz(string path) {
    assert(0);
  }

  void unpackZip(string path) {
    assert(0);
  }

public:

  void open() {
    nfdchar_t* outPath;
    switch (NFD_OpenDialog(openFilters, openPath, &outPath)) {
    case NFD_CANCEL:
      // Do nothing.
      break;

    case NFD_OKAY:
      scope (exit) outPath.free();
      open(outPath.to!string);
      break;

    default:
      throw new Exception(NFD_GetError().to!string);
    }
  }

  void _open(string path) {
    thread.power(false);

    auto ext = path.extension;
    enforce(ext !is null, "Don't know how to open file: " ~ path);

    file = path;
    ext  = ext[1..$]; // Remove the period before the extension

    if (auto open = ext in loader.unpacksByFileExtension) {
      (*open)(path);
    }
    else {
      setSystemFromExt(ext);
      _current.load(path);
    }

    assert(_current);
    _current.power();

    recent.add(path);
    imgui.gameLayout();

    thread.power(true);
  }

  void open(string path) {
    try {
      _open(path);
    }
    catch (Exception e) {
      lastException = e;
      console.error(e.msg);
    }
  }

  void setSystemFromExt(string ext) {
    auto current = ext in loader.systemsByFileExtension;
    enforce(current !is null, "Not a valid or supported ROM extension: " ~ ext);

    _current = *current;
  }
}

/**
 * Handling of recently opened files.
 */
public struct recent {
  mixin util.noCtors!();

  private static __gshared {
    string[] _files; /// List of recently opened files.
    bool     _dirty; /// Whether the list has changed since it was loaded.
  }

  /// Name of the storage file containing line-separated recent files data.
  enum storageFile = "recent-files.txt";

  private alias initialize = load;
  private alias terminate  = save;

  /// Loads the recent file at the given index.
  static void open(uint index) {
    loader.open(_files[index]);
  }

  /// Loads the recent files list from storage.
  static void load() {
    _files = user.readTextLines(storageFile);
    _dirty = false;
  }

  /// Saves the recent files list to storage.
  static void save() {
    if (_dirty) {
      user.writeTextLines(storageFile, _files);

      _dirty = false;
    }
  }

  /// Adds a file to the recent list.
  static void add(string path) {
    _files ~= path;

    if (_files.length > _settings.maxRecentFiles) {
      _files.length = _settings.maxRecentFiles;
    }

    _dirty = true;
  }

  /// Clears the recent files list.
  static void clear() {
    if (!_files.empty) {
      _files = null;
      _dirty = true;
    }
  }

  /// Returns the number of entries in the recent files list.
  static uint length() {
    return _files.length.to!uint;
  }

  /// Returns the list of recently opened files.
  static string[] files() nothrow @nogc {
    return _files;
  }
}

/**
 * Serialization of application state.
 */
public struct state {
static:
  mixin util.noCtors!();

  enum autoSaveName = "auto.stsv";

  private void initialize() {
    // TODO: auto reload?
  }

  private void terminate() {
    // TODO: auto store?
  }

  /// Currently active quick save/load slot.
  private __gshared uint _quickSlot;
  /// ditto
  uint quickSlot() nothrow @nogc {
    return _quickSlot;
  }
  /// ditto
  void quickSlot(uint index) {
    enforce(index < 10);
    _quickSlot = index;
  }

  /// Indirectly stores the current state using quickSlot.
  void quickSave() {
    save(_quickSlot);
  }
  /// Indirectly restores the current state using quickSlot.
  void quickLoad() {
    load(_quickSlot);
  }

  /// Stores the current application state.
  void save(uint slot) {
    enforce(slot < 10);
    // TODO:
  }
  /// Restores the current application state.
  void load(uint slot) {
    enforce(slot < 10);
    // TODO:
  }
}
