/**
 * D Emulator.
 */
module app;

import std = core.stdc.stdlib;

import std.array : empty;

import opt = std.getopt;
import sio = std.stdio;

import emulator = emulator.system;
import script   = emulator.script;

// import gameboy.system : GameBoy;
// import nes.system     : NES;
import snes.system    : SNES;

private:

/// Application entry point. Receives the command-line arguments.
void main(string[] args) {
  try args.parse();
  catch (Exception e) fatal(e.msg);

  // TODO: more systems
  // new GameBoy().register;
  // new NES().register;
  new SNES().register;

  emulator.run();
}

/// Parses command-line arguments. Separate function in order to not pollute main's stack.
void parse(string[] args) {
  opt.endOfOptions = "";

  string   config;
  string[] cheats;
  bool     noInit;
  bool     wantBreak;
  auto helpInfo = opt.getopt(args,
                             opt.config.caseSensitive,
                             opt.config.bundling,
                             "init|f",  "Init file.",         &config,
                             "no-init", "Disable init file.", &noInit,
                             "break|b", "Break on start.",    &wantBreak,
                             "cheat|c", "Add cheat code.",    &cheats,
                             "quiet|q", "Quiet mode.",        &emulator.hideAlerts);

  if (helpInfo.helpWanted) {
    opt.defaultGetoptPrinter("DSNES 1.0.", helpInfo.options);
    std.exit(std.EXIT_SUCCESS);
  }

  // Scripting file to load before system initialization.
  if (!config.empty) {
    if (noInit) fatal("--init and --no-init are mutually exclusive.");

    // script.initFile = config;
  }
  else if (noInit) {
    // script.initFile = null;
  }

  // Emulator file to load after system initialization.
  switch (args.length) {
  case 1:  break;
  case 2:  emulator.file = args[1]; break;
  default: fatal("Too many arguments.");
  }

  // TODO: wantBreak
}

void fatal(string message) {
  sio.stderr.writeln(message);
  std.exit(std.EXIT_FAILURE);
}
