/**
 * Low-level profiling utilities. Used to gather performance data every frame.
 */
module emulator.profiler;

import util = emulator.util;

/// Whether support for profiling the application is available.
enum enabled = util.featureEnabled!"Profiler";

// Disabled
// -----------------------------------------------------------------------------

static if (!enabled) {
  scope class    Profile() {}
  scope class GpuProfile() {}

  package void initialize() {}
  package void terminate () {}

  package void run() {}
  package void end() {}
}

// Enabled
// -----------------------------------------------------------------------------

static if (enabled):

import core.stdc.stdlib : malloc, free;

import core.time : MonoTime;
import core.thread;

import core.sync.rwmutex : ReadWriteMutex;

import std.array : Appender;
import std.conv  : text, to;

import imgui;

import emulator.util : cstring;

/// Values configurable by the user.
struct Settings {
  long historyMaxLength = -1; /// Maximum history frames. -1 for unlimited.
}

/// Thread-local index into the profile markers.
private ubyte threadIndex;
/// ditto
private ubyte getThreadIndex() {
  static __gshared ubyte _nextThreadIndex = 1;

  auto index = threadIndex;
  if (index == 0) {
    index = threadIndex = _nextThreadIndex++;
  }
  return index;
}

private __gshared {
  Settings settings;

  Appender!(Snapshot[]) _history; /// Previously captured frames.
  Appender!(Marker[])[] _markers; /// Per thread markers for the current frame.

  ReadWriteMutex _sync;
}

struct Marker {
  // Timing
  MonoTime start;
  MonoTime stop;
  // Hierarchy
  uint parent;
  ushort childCount;
  // Display
  ushort lineNumber;
  ushort nameLength;
  ushort fileLength;
  cstring name;
  cstring file;
  ImVec4 color;
}

struct Snapshot {
  uint markerStart;
  uint markerEnd;
}

// Threads are free from the framerate, they may be running during a new frame.
// This means snapshots have to slice markers that are not from the main thread.

// This has to be done in a thread-safe manner.
// - RW lock? each thread gets a read lock on their view and main thread gets write
// -

// ||||||||||||||
// |||||||||||||
// ||||||||||
// ||||||||||||||||

// Marker and Events
// -----------------------------------------------------------------------------

/// Adds a new marker on the profiling stack for the current frame.
Marker* push() nothrow @nogc {
  Marker* result;

  // Get thread index
  // Appender?

  // result.start = MonoTime.currTime;
  return result;
}

void pop(Marker* marker) nothrow @nogc {
  assert(marker !is null);
  // marker.stop = MonoTime.currTime;


}

/// Profiling markers. Allocate on the stack for exception-safety.
scope class Profile(string name = __FUNCTION__,
                    string file = __FILE__,
                    uint   line = __LINE__)
{
  nothrow @nogc:

  private Marker* _marker;

  this() {
    _marker = push();
    // _marker.lineNumber = line;
    // _marker.fileLength = cast(ushort) file.length;
    // _marker.nameLength = cast(ushort) name.length;
    // _marker.file = file.ptr;
    // _marker.name = name.ptr;
  }

  ~this() {
    // pop(_marker);
  }
}
unittest {
  scope auto p = new Profile!();
}

/// GPU profiling markers. Allocate on the stack for exception-safety.
scope class GpuProfile(string name = __FUNCTION__,
                       string file = __FILE__,
                       uint   line = __LINE__)
{
  this() {

  }

  ~this() {

  }
}

// Lifecycle
// -----------------------------------------------------------------------------

package void initialize() {
  _sync = new ReadWriteMutex();
}

package void terminate() {
  delete _sync;
}

/// Start collecting profiling data.
void start() {
  synchronized (_sync.writer) {

  }
}

void stop() {
  synchronized (_sync.writer) {

  }
}

void run() {
  synchronized (_sync.writer) {

  }
}

void end() {
  synchronized (_sync.writer) {

  }
}
