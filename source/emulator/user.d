/**
 * Utilities to manage user configuration.
 *
 * Exposes a few useful directory.
 * - Home directory :: The current user's personal directory.
 * - Data directory :: Contains application data files for the current user.
 * - Font directories :: The folders containing fonts available to the GUI.
 */
module emulator.user;

import core.stdc.stdlib : getenv;

import std.array : empty, join, split;
import std.conv  : to;
import std.file  : getcwd, exists, mkdirRecurse, readText, write;
import std.path  : buildPath, isAbsolute;

import emulator.util : cstring;
import console = emulator.console;
import product = emulator.product;

// Public Variables
// -----------------------------------------------------------------------------

/// The application data directory for the current user.
private __gshared string _dataPath;
/// ditto
string dataPath() nothrow @nogc { return _dataPath; }

/// The user's home directory.
private __gshared string _homePath;
/// ditto
string homePath() nothrow @nogc { return _homePath; }
/// ditto
private void homePath(string path) {
  _homePath = path;
  _dataPath = path.buildPath("." ~ product.shortName);
}

/// Returns the system and user font paths.
string[] fontPaths() {
  version (linux) {
    // TODO: use fontconfig?
    return [homePath.buildPath("fonts"),
            "/usr/local/share/fonts",
            "/usr/share/fonts"];
  }
  else version (OSX) {
    enum path = "/Library/Fonts";
    return [homePath.buildPath(path[1..$]), path];
  }
  else version (Windows) {
    auto windir = "WINDIR".getenv().to!string;
    if (windir.empty) {
      windir = "C:\\Windows";
    }
    return [windir.buildPath("fonts")];
  }
  else {
    pragma(msg, "Don't know how to get system font paths.");
    return [];
  }
}

// Life-Cycle
// -----------------------------------------------------------------------------

package:

void initialize() {
  /**/ version (Posix)   enum homeDirs = ["HOME"];
  else version (Windows) enum homeDirs = ["APPDATA", "HOME"];
  else static assert(0);

  foreach (var; homeDirs) {
    if (auto path = getenv(var.ptr)) {
      homePath = path.to!string;
      break;
    }
  }

  if (homePath is null) {
    console.warn("Home not found, trying install directory");
    homePath = getcwd();
  }

  assert(!dataPath.empty);
  console.verbose("Data: ", dataPath);

  if (!dataPath.exists) {
    dataPath.mkdirRecurse();
  }
}

void terminate() {
  _dataPath = null;
  _homePath = null;
}

// Internal utilities
// -----------------------------------------------------------------------------

string makePath(string file) {
  return file.isAbsolute ? file : homePath.buildPath(file);
}

string readTextFile(string file) {
  auto path = file.makePath();
  return path.exists() ? path.readText() : null;
}

void writeTextFile(string file, string contents) {
  file.makePath.write(contents);
}

string[] readTextLines(string file) {
  return file.readTextFile().split("\n");
}

void writeTextLines(string file, string[] lines) {
  file.writeTextFile(lines.join("\n"));
}
