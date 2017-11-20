module emulator.audio;

import std.conv : to;

import derelict.sdl2.sdl;

import emulator.util : dispose, sdlRaise;

import console = emulator.console;

private __gshared {
  SDL_AudioSpec spec;
  SDL_AudioDeviceID dev;
}

package:

void initialize() {
  console.trace("Initialize");

  foreach (n; 0 .. SDL_GetNumAudioDrivers()) {
    console.verbose("Audio Driver: #", n, " ", SDL_GetAudioDriver(n).to!string);
  }

  foreach (n; 0 .. SDL_GetNumAudioDevices(0)) {
    console.verbose("Audio Device: #", n, " ", SDL_GetAudioDeviceName(n, 0).to!string);
  }

  SDL_AudioSpec want;
  want.freq     = 48_000;
  want.format   = AUDIO_F32;
  want.channels = 2;
  want.samples  = 4096;
  want.callback = &callback;

  import emulator.util;
  auto s = SDL_LoadWAV("files/a.wav", &want, &buf, &len).sdlCheck;
  s.callback = &callback;

  // dev = SDL_OpenAudioDevice("HDMI", 0, s, &spec, 0);
  // if (dev == 0) sdlRaise();

  // SDL_PauseAudioDevice(dev, false);
}

__gshared { // XXX:
  ubyte* buf;
  uint len;
}

void terminate() {
  console.trace("Terminate");

  if (DerelictSDL2.isLoaded) {
    dev.dispose!SDL_CloseAudioDevice();
  }
}

void run() {

}

uint pos;
nothrow:

extern (C) void callback(void* userData, ubyte* stream, int length) {
  if (len == 0) return;
  length = length > len ? len : length;
  stream[0..length] = buf[pos..pos+length];
  // SDL_MixAudioFormat(stream, buf + pos, spec.format, length, SDL_MIX_MAXVOLUME / 2);

  pos += length;
  len -= length;
}
