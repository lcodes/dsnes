/**
 *
 */
module emulator.audio;

import std.conv      : text, to;
import std.exception : enforce;

import derelict.openal;

import emulator.profiler : Profile;
import emulator.util : cstring, dispose;

import console = emulator.console;

// Audio state
// -----------------------------------------------------------------------------

private __gshared {
  ALCdevice*  device;
  ALCcontext* context;

  Settings settings;

  struct Settings {
    cstring device;
  }
}

// Lifecycle
// -----------------------------------------------------------------------------

package:

void initialize() {
  console.trace("Initialize");
  assert(!DerelictAL.isLoaded);

  DerelictAL.load();

  if (alcIsExtensionPresent(null, "ALC_ENUMERATION_EXT")) {
    auto list = alcGetString(null, ALC_DEVICE_SPECIFIER);
    do {
      auto dev = list.to!string;
      list += dev.length + 1;

      console.verbose("Detected device: ", dev);
    } while (*list);
  }

  device = alcOpenDevice(settings.device);
  if (!device && settings.device) {
    device = alcOpenDevice(null);
    enforce(device, "Failed to open device");

    console.warn("Requested device '", settings.device, "' was not found. ",
                 "Falling back to using the default device.");
  }

  console.verbose("Using device: ", device.alcGetString(ALC_DEVICE_SPECIFIER));

  context = device.alcCreateContext(null);
  enforce(context, "Failed to create device context");

  context.alcMakeContextCurrent();
  alCheck();
}

void terminate() {
  console.trace("Terminate");

  if (DerelictAL.isLoaded) {
    alcMakeContextCurrent(null);

    context.dispose!alcDestroyContext;
    device .dispose!alcCloseDevice;

    DerelictAL.unload();
  }
}

void run() {
  scope auto p = new Profile!();

}

private:

// Utilities
// -----------------------------------------------------------------------------

void alCheck(uint line = __LINE__)() {
  auto e = alGetError();
  if (e == AL_NO_ERROR) return;

  string msg;
  switch (e) {
  default: assert(0, "Unknown AL error");
  case AL_INVALID_NAME:      msg = "Invalid name";      break;
  case AL_INVALID_ENUM:      msg = "Invalid enum";      break;
  case AL_INVALID_VALUE:     msg = "Invalid value";     break;
  case AL_INVALID_OPERATION: msg = "Invalid operation"; break;
  case AL_OUT_OF_MEMORY:     msg = "Out of memory";     break;
  }

  throw new Exception(text("AL: ", msg, "\n @ ", __FILE__, ":", line));
}
