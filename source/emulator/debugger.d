/**
 *
 */
module emulator.debugger;

import util = emulator.util;

/// Whether support for debugging emulated programs is available.
enum enabled = util.featureEnabled!"Debugger";

// Disabled
// -----------------------------------------------------------------------------

static if (!enabled) {

}

// Enabled
// -----------------------------------------------------------------------------

static if (enabled):
