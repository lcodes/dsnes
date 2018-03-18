/**
 * Emulator application entry point.
 *
 * Parses the environment and command-line then launches the emulator system.
 */
module app;

import std = core.stdc.stdlib;

import std.array : empty;
import std.conv  : to;
import std.meta  : AliasSeq;

import opt = std.getopt;
import sio = std.stdio;
import str = std.string;

import cheats   = emulator.cheats;
import console  = emulator.console : LogLevel;
import debugger = emulator.debugger;
import product  = emulator.product;
import profiler = emulator.profiler;
import script   = emulator.script;
import system   = emulator.system : Quit;

import snes.system : SNES;

// Entry Point
// -----------------------------------------------------------------------------

private:

/// Main application entry point.
int main(string[] args) {
  int exitCode;

  try {
    args.parse();

    new SNES().register;

    system.run();

    exitCode = std.EXIT_SUCCESS;
  }
  catch (Quit e) {
    exitCode = e.exitCode;
  }
  catch (Exception e) {
    exitCode = std.EXIT_FAILURE;

    debug auto msg = e.toString();
    else  auto msg = e.msg;
    system.fatal(msg);
  }

  return exitCode;
}

// Command-line arguments
// -----------------------------------------------------------------------------

/// Parses command-line arguments.
void parse(string[] args) {
  opt.endOfOptions = "";

  // Setup
  // ---------------------------------------------------------------------------

  // Generic options. These are always supported.
  string[] cheats;
  string   config;
  string   home;

  config.fromEnv!"CONFIG"();
  home  .fromEnv!"HOME";

  // Default logging level. Configuration file overrides unless user-defined.
  LogLevel logLevel = LogLevel.info;
  debug    logLevel = LogLevel.trace; // Change the default in development.

  logLevel.fromEnv!"LOG_LEVEL"();

  void changeLogLevel(int mod)() {
    logLevel = cast(LogLevel) (logLevel + mod);
  }

  // Scripting can load and run an user initialization file.
  static if (script.enabled) {
    string _init;
    bool _noInit;
    auto init   = &_init;
    auto noInit = &_noInit;

    _init  .fromEnv!"INIT"();
    _noInit.fromEnv!"NO_INIT"();

    alias scriptOptions =
      AliasSeq!("init|l",  "LUA initialization file.",          init,
                "no-init", "Disables LUA initialization file.", noInit);
  }
  else {
    enum scriptOptions = AliasSeq!();
  }

  // Debugging can trigger breakpoints from launch.
  static if (debugger.enabled) {
    bool _break;
    auto break_ = &_break;

    _break.fromEnv!"BREAK"();

    alias debugOptions =
      AliasSeq!("break|b", "Trigger a breakpoint on start.", break_);
  }
  else {
    alias debugOptions = AliasSeq!();
  }

  // Profiling can be enabled from launch.
  static if (profiler.enabled) {
    bool _profile;
    auto profile = &_profile;

    _profile.fromEnv!"PROFILE"();

    alias profileOptions =
      AliasSeq!("profile|p", "Start profiling from launch.", profile);
  }
  else {
    alias profileOptions = AliasSeq!();
  }

  // Parse
  // ---------------------------------------------------------------------------

  // Actually parse the options.
  auto helpInfo = opt.getopt
    (args,
     opt.config.caseSensitive,
     opt.config.bundling,
     AliasSeq!(scriptOptions,
               debugOptions,
               profileOptions),
     "cheat|c",   "Add one or more cheat codes.",   &cheats,
     "log-level", "Set the cmdline logging level.", &logLevel,
     "quiet|q",   "Disable most logging messages.", &changeLogLevel!(-1),
     "verbose|v", "Enable more logging messages",   &changeLogLevel!(+1));

  // Display a help message and quit.
  if (helpInfo.helpWanted) {
    opt.defaultGetoptPrinter("DEMU 1.0.", helpInfo.options);
    std.exit(std.EXIT_SUCCESS);
  }

  // TODO: load configuration here!

  // Apply
  // ---------------------------------------------------------------------------

  // Override configuration settings.
  console.setLogLevel(logLevel);

  // Scripting file to load after application initialization.
  static if (script.enabled) {
    if (!_init.empty) {
      if (_noInit) {
        system.fatal("--init and --no-init are mutually exclusive.");
      }

      script.initFile = _init;
    }
    else if (noInit) {
      script.initFile = null;
    }
  }

  // Apply cheating options.
  // static if (cheats.enabled) {

  // }

  // Apply debugging options.
  static if (debugger.enabled) if (_break) {
    // TODO:
  }

  // Apply profiling options.
  static if (profiler.enabled) if (profile) {
    profiler.start();
  }

  // Emulator file to load after system initialization.
  switch (args.length) {
  case 1:  break;
  case 2:  system.file = args[1]; break;
  default: system.fatal("Too many arguments.");
  }
}

// Utilities
// -----------------------------------------------------------------------------

enum envPrefix = str.toUpper(product.shortName);

const(char)* getenv(string name)() {
  enum var = envPrefix ~ "_" ~ name;
  return std.getenv(cast(const char*) var.ptr);
}

/// Overrides a variable if its matching environment variable is defined.
void fromEnv(string name, T)(ref T var) if (is(T : bool)) {
  if (auto val = getenv!name()) {
    auto str = str.toLower(val.to!string);
    var = str.length == 0 ||
      (str != "0" &&
       str != "false" &&
       str != "no" &&
       str != "off");
  }
}
/// ditto
void fromEnv(string name, T)(ref T var) if (!is(T : bool)) {
  if (auto str = getenv!name()) {
    var = str.to!string.to!T;
  }
}
