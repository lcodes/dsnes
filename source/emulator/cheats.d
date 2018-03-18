/**
 * Support for cheating devices such as the Action Replay or Game Genie.
 *
 * Depending on where in memory the cheat is targeted, the behavior changes:
 * - ROM :: Applied once after a cartridge is loaded. Memory can't change.
 * - RAM :: Applied after every write to prevent the value from changing.
 * - I/O :: Applied on every read. TODO: what about writes?
 */
module emulator.cheats;

import std.conv : parse;

import emulator.util : featureEnabled;

/// Whether support for cheat codes is available.
enum enabled = featureEnabled!"Cheats";

// Disabled
// -----------------------------------------------------------------------------

static if (!enabled) {

}

// Enabled
// -----------------------------------------------------------------------------

static if (enabled):

class CheatException : Exception {
  this(string code, Throwable cause) {
    super("Invalid cheat code: " ~ code, cause);
  }
}

/// Parses a cheat code into an address and value override.
void parseCode(string code, ref uint address, ref ubyte value) {
  try switch (code.length) {
  default: throw new Exception("Unknown cheat code format.");

  // Action Replay
  case 8:
    auto addressStr = code[0..6];
    auto valueStr   = code[6..$];
    address = addressStr.parse!uint (16);
    value   = valueStr  .parse!ubyte(16);
    break;

  // Game Genie
  case 9:
    assert(0, "TODO");
    // break;
  }
  catch (Exception cause) {
    throw new CheatException(code, cause);
  }
}
unittest {
  // SNES: 7E122F01
  // SNES: C264-64D7
}

/// Registers a new cheat code.
void addCode(string code) {
  uint address;
  ubyte value;
  code.parseCode(address, value);
  addCode(address, value);
}
/// ditto
void addCode(uint address, ubyte value) {

}

/// Unregisters an existing cheat code.
void removeCode(string code) {
  uint address;
  ubyte value;
  code.parseCode(address, value);
  removeCode(address, value);
}
/// ditto
void removeCode(uint address, ubyte value) {

}
