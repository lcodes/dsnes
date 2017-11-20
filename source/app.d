module app;

import std = core.stdc.stdlib;

import opt = std.getopt;
import sio = std.stdio;

private:

void main(string[] args) {
  try args.parse();
  catch (Exception e) fatal(e.msg);
}

void parse(string[] args) {
  opt.endOfOptions = "";

  auto helpInfo = opt.getopt(args,
                             opt.config.caseSensitive,
                             opt.config.bundling);

  if (helpInfo.helpWanted) {
    opt.defaultGetoptPrinter("Emulator 0.1.0.", helpInfo.options);
    std.exit(std.EXIT_SUCCESS);
  }

  switch (args.length) {
  case 1:  break;
  case 2:  /* TODO: load file */ break;
  default: fatal("Too many arguments.");
  }
}

void fatal(string message) {
  sio.stderr.writeln(message);
  std.exit(std.EXIT_FAILURE);
}
