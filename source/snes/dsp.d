module snes.dsp;

import std.bitmanip : bitfields;

import emulator.util : bits, sclamp;

import thread = emulator.thread;

import smp = snes.smp;

private __gshared {
  thread.Processor proc;

  State state;
  Voice[8] voice;

  enum : ubyte {
    MVOLL = 0x0c, MVOLD = 0x1c,
    EVOLL = 0x2c, EVOLR = 0x3c,
    KON   = 0x4c, KOFF  = 0x5c,
    FLG   = 0x6c, ENDX  = 0x7c,
    EFB   = 0x0d, PMON  = 0x2d,
    NON   = 0x3d, EON   = 0x4d,
    DIR   = 0x5d, ESA   = 0x6d,
    EDL   = 0x7d, FIR   = 0x0f  // 8 coefficients at 0x0f, 0x1f, ... 0x7f
  }

  enum : ubyte {
    VOLL   = 0x00, VOLR   = 0x01,
    PITCHL = 0x02, PITCHH = 0x03,
    SRCN   = 0x04, ADSR0  = 0x05,
    ADSR1  = 0x06, GAIN   = 0x07,
    ENVX   = 0x08, OUTX   = 0x09
  }

  enum : ubyte {
    EnvelopeRelease,
    EnvelopeAttack,
    EnvelopeDecay,
    EnvelopeSustain
  }

  enum {
    BrrBlockSize = 9,
    CounterRange = 2048 * 5 * 3 // 30720 (0x7800)
  }

  struct State {
    union {
      ubyte[128] uregs;
       byte[128] sregs;
    }

    int[8][2] echoHistory; // Echo history keeps the most recent 8 stereo samples.
    mixin(bitfields!(int,  "echoHistoryOffset", 3,
                     bool, "everyOtherSample",  1, // Toggles every sample.
                     byte, "unused",            4));

    int kon;  // KON value when last checked.
    int noise;
    int counter;
    int echoOffset; // Offset from ESA in echo buffer.
    int echoLength; // Number of bytes that echoOffset will stop at.

    // Hidden registers also written to when main register is written to.
    int konBuffer;
    int endxBuffer;
    int envxBuffer;
    int outxBuffer;

    // Temporary state between clocks, prefixed with _.

    // Read once per sample.
    int _pmon;
    int _non;
    int _eon;
    int _dir;
    int _koff;

    // Read a few clocks ahead before used.
    int _brrNextAddress;
    int _adsr0;
    int _brrHeader;
    int _brrByte;
    int _srcn;
    int _esa;
    int _echoDisabled;

    // Internal state that is recalculated every sample.
    int _dirAddress;
    int _pitch;
    int _output;
    int _looped;
    int _echoPointer;

    // Left/right sums.
    int[2] _mainOut;
    int[2] _echoOut;
    int[2] _echoIn;
  }

  struct Voice {
    int[12 * 3] buffer; // 12 decoded samples (mirrored for wrapping).
    int bufferOffset;   // Place in buffer where next samples will be decoded.
    int gaussianOffset; // Relative fractional position in sample (0x1000 = 1.0).
    int brrAddress;     // Address of current BRR block.
    int brrOffset;      // Current decoding offset in BRR block.
    int vbit;           // Bitmask for voice: 0x01 for voice 0, 0x02 for voice 1, etc.
    int vidx;           // Voice channel register index: 0x00 for voice 0, 0x10 for voice 1, etc.
    int konDelay;       // KON delay/current setup phase.
    int envelopeMode;
    int envelope;       // Current envelope level.
    int hiddenEnvelope; // Used by GAIN mode 7, very obscure quirk.
    int _envxOut;
  }
}

// Core
// -------------------------------------------------------------------------------------------------

nothrow @nogc {
  thread.Processor processor() { return proc; }
}

package:

void initialize() {}
void terminate() {}

void power() {
  proc = thread.create(&entry, 32040.0 * 768.0);
  // TODO: audio stream

  state = State.init;
  state.noise = 0x4000;
  state.everyOtherSample = 1;

  voice[] = Voice.init;

  foreach (n; 0..8) {
    voice[n].brrOffset = 1;
    voice[n].vbit = 1 << n;
    voice[n].vidx = n * 0x10;
  }

  state.uregs[FLG] = 0xe0;
}

private:

void entry() {
  while (true) {
    thread.synchronize();
    run();
  }
}

void step(uint clocks) {
  proc.step(clocks);
}

void tick() {
  step(3 * 8);
  processor.synchronize(smp.processor);
}

void run() {
  voice5(voice[0]);
  voice2(voice[1]);
  tick();

  voice6(voice[0]);
  voice3(voice[1]);
  tick();

  voice7(voice[0]);
  voice4(voice[1]);
  voice1(voice[3]);
  tick();

  voice8(voice[0]);
  voice5(voice[1]);
  voice2(voice[2]);
  tick();

  voice9(voice[0]);
  voice6(voice[1]);
  voice3(voice[2]);
  tick();

  voice7(voice[1]);
  voice4(voice[2]);
  voice1(voice[4]);
  tick();

  voice8(voice[1]);
  voice5(voice[2]);
  voice2(voice[3]);
  tick();

  voice9(voice[1]);
  voice6(voice[2]);
  voice3(voice[3]);
  tick();

  voice7(voice[2]);
  voice4(voice[3]);
  voice1(voice[5]);
  tick();

  voice8(voice[2]);
  voice5(voice[3]);
  voice2(voice[4]);
  tick();

  voice9(voice[2]);
  voice6(voice[3]);
  voice3(voice[4]);
  tick();

  voice7(voice[3]);
  voice4(voice[4]);
  voice1(voice[6]);
  tick();

  voice8(voice[3]);
  voice5(voice[4]);
  voice2(voice[5]);
  tick();

  voice9(voice[3]);
  voice6(voice[4]);
  voice3(voice[5]);
  tick();

  voice7(voice[4]);
  voice4(voice[5]);
  voice1(voice[7]);
  tick();

  voice8(voice[4]);
  voice5(voice[5]);
  voice2(voice[6]);
  tick();

  voice9(voice[4]);
  voice6(voice[5]);
  voice3(voice[6]);
  tick();

  voice1(voice[0]);
  voice7(voice[5]);
  voice4(voice[6]);
  tick();

  voice8(voice[5]);
  voice5(voice[6]);
  voice2(voice[7]);
  tick();

  voice9(voice[5]);
  voice6(voice[6]);
  voice3(voice[7]);
  tick();

  voice1(voice[1]);
  voice7(voice[6]);
  voice4(voice[7]);
  tick();

  voice8(voice[6]);
  voice5(voice[7]);
  voice2(voice[0]);
  tick();

  voice3a(voice[0]);
  voice9(voice[6]);
  voice6(voice[7]);
  echo22();
  tick();

  voice7(voice[7]);
  echo23();
  tick();

  voice8(voice[7]);
  echo24();
  tick();

  voice3b(voice[0]);
  voice9(voice[7]);
  echo25();
  tick();

  echo26();
  tick();

  misc27();
  echo27();
  tick();

  misc28();
  echo28();
  tick();

  misc29();
  echo29();
  tick();

  misc30();
  voice3c(voice[0]);
  echo30();
  tick();

  voice4(voice[0]);
  voice1(voice[2]);
  tick();
}

ref auto reg(ref Voice v, int n) { return state.uregs[v.vidx + n]; }

// Gaussian
// -------------------------------------------------------------------------------------------------

immutable short[512] gaussianTable = [
     0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
     1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    1,    2,    2,    2,    2,    2,
     2,    2,    3,    3,    3,    3,    3,    4,    4,    4,    4,    4,    5,    5,    5,    5,
     6,    6,    6,    6,    7,    7,    7,    8,    8,    8,    9,    9,    9,   10,   10,   10,
    11,   11,   11,   12,   12,   13,   13,   14,   14,   15,   15,   15,   16,   16,   17,   17,
    18,   19,   19,   20,   20,   21,   21,   22,   23,   23,   24,   24,   25,   26,   27,   27,
    28,   29,   29,   30,   31,   32,   32,   33,   34,   35,   36,   36,   37,   38,   39,   40,
    41,   42,   43,   44,   45,   46,   47,   48,   49,   50,   51,   52,   53,   54,   55,   56,
    58,   59,   60,   61,   62,   64,   65,   66,   67,   69,   70,   71,   73,   74,   76,   77,
    78,   80,   81,   83,   84,   86,   87,   89,   90,   92,   94,   95,   97,   99,  100,  102,
   104,  106,  107,  109,  111,  113,  115,  117,  118,  120,  122,  124,  126,  128,  130,  132,
   134,  137,  139,  141,  143,  145,  147,  150,  152,  154,  156,  159,  161,  163,  166,  168,
   171,  173,  175,  178,  180,  183,  186,  188,  191,  193,  196,  199,  201,  204,  207,  210,
   212,  215,  218,  221,  224,  227,  230,  233,  236,  239,  242,  245,  248,  251,  254,  257,
   260,  263,  267,  270,  273,  276,  280,  283,  286,  290,  293,  297,  300,  304,  307,  311,
   314,  318,  321,  325,  328,  332,  336,  339,  343,  347,  351,  354,  358,  362,  366,  370,
   374,  378,  381,  385,  389,  393,  397,  401,  405,  410,  414,  418,  422,  426,  430,  434,
   439,  443,  447,  451,  456,  460,  464,  469,  473,  477,  482,  486,  491,  495,  499,  504,
   508,  513,  517,  522,  527,  531,  536,  540,  545,  550,  554,  559,  563,  568,  573,  577,
   582,  587,  592,  596,  601,  606,  611,  615,  620,  625,  630,  635,  640,  644,  649,  654,
   659,  664,  669,  674,  678,  683,  688,  693,  698,  703,  708,  713,  718,  723,  728,  732,
   737,  742,  747,  752,  757,  762,  767,  772,  777,  782,  787,  792,  797,  802,  806,  811,
   816,  821,  826,  831,  836,  841,  846,  851,  855,  860,  865,  870,  875,  880,  884,  889,
   894,  899,  904,  908,  913,  918,  923,  927,  932,  937,  941,  946,  951,  955,  960,  965,
   969,  974,  978,  983,  988,  992,  997, 1001, 1005, 1010, 1014, 1019, 1023, 1027, 1032, 1036,
  1040, 1045, 1049, 1053, 1057, 1061, 1066, 1070, 1074, 1078, 1082, 1086, 1090, 1094, 1098, 1102,
  1106, 1109, 1113, 1117, 1121, 1125, 1128, 1132, 1136, 1139, 1143, 1146, 1150, 1153, 1157, 1160,
  1164, 1167, 1170, 1174, 1177, 1180, 1183, 1186, 1190, 1193, 1196, 1199, 1202, 1205, 1207, 1210,
  1213, 1216, 1219, 1221, 1224, 1227, 1229, 1232, 1234, 1237, 1239, 1241, 1244, 1246, 1248, 1251,
  1253, 1255, 1257, 1259, 1261, 1263, 1265, 1267, 1269, 1270, 1272, 1274, 1275, 1277, 1279, 1280,
  1282, 1283, 1284, 1286, 1287, 1288, 1290, 1291, 1292, 1293, 1294, 1295, 1296, 1297, 1297, 1298,
  1299, 1300, 1300, 1301, 1302, 1302, 1303, 1303, 1303, 1304, 1304, 1304, 1304, 1304, 1305, 1305
];

int gaussianInterpolate(ref const Voice v) {
  // Make pointers into gaussian table based on fractional position between samples.
  int offset = v.gaussianOffset >> 4;
  auto forward = gaussianTable.ptr + 255 - offset;
  auto reverse = gaussianTable.ptr       + offset;  // Mirror left half of gaussian table.

  offset = 12 + v.bufferOffset + (v.gaussianOffset >> 12);
  int output;
  output  = (forward[  0] * v.buffer[offset + 0]) >> 11;
  output += (forward[256] * v.buffer[offset + 1]) >> 11;
  output += (reverse[256] * v.buffer[offset + 2]) >> 11;
  output  = cast(short)output;
  output += (reverse[  0] * v.buffer[offset + 3]) >> 11;
  return sclamp!16(output) & ~1;
}

// Counter
// -------------------------------------------------------------------------------------------------

// counter_rate = number of samples per counter event
// all rates are evenly divisible by counter_range (0x7800, 30720, or 2048 * 5 * 3)
// note that rate[0] is a special case, which never triggers
immutable ushort[32] counterRate = [
     0, 2048, 1536,
  1280, 1024,  768,
   640,  512,  384,
   320,  256,  192,
   160,  128,   96,
    80,   64,   48,
    40,   32,   24,
    20,   16,   12,
    10,    8,    6,
     5,    4,    3,
           2,
           1,
];

//counter_offset = counter offset from zero
//counters do not appear to be aligned at zero for all rates
immutable ushort[32] counterOffset = [
    0, 0, 1040,
  536, 0, 1040,
  536, 0, 1040,
  536, 0, 1040,
  536, 0, 1040,
  536, 0, 1040,
  536, 0, 1040,
  536, 0, 1040,
  536, 0, 1040,
  536, 0, 1040,
       0,
       0,
];

void counterTick() {
  state.counter--;
  if (state.counter < 0) state.counter = CounterRange - 1;
}

// Return true if counter event should trigger
bool counterPoll(uint rate) {
  if (rate == 0) return false;
  return ((cast(uint) state.counter + counterOffset[rate]) % counterRate[rate]) == 0;
}

// Envelope
// -------------------------------------------------------------------------------------------------

void envelopeRun(ref Voice v) {
  auto envelope = v.envelope;

  if (v.envelopeMode == EnvelopeRelease) { // 60%
    envelope -= 0x8;
    if (envelope < 0) envelope = 0;
    v.envelope = envelope;
    return;
  }

  int rate;
  auto envelopeData = v.reg(ADSR1);
  if (state._adsr0 & 0x80) { // 99% ADSR
    if (v.envelopeMode >= EnvelopeDecay) { // 99%
      envelope--;
      envelope -= envelope >> 8;
      rate = envelopeData & 0x1f;
      if (v.envelopeMode == EnvelopeDecay) { // 1%
        rate = ((state._adsr0 >> 3) & 0x0e) + 0x10;
      }
    }
    else { // EnvelopeAttack
      rate = ((state._adsr0  & 0x0f) << 1) + 1;
      envelope += rate < 31 ? 0x20 : 0x400;
    }
  }
  else { // Gain
    envelopeData = v.reg(GAIN);
    auto mode = envelopeData >> 5;
    if (mode < 4) { // Direct
      envelope = envelopeData << 4;
      rate = 31;
    }
    else {
      rate = envelopeData & 0x1f;
      if (mode == 4) { // 4: Linear decrease.
        envelope -= 0x20;
      }
      else if (mode < 6) { // 5: Exponential decrease.
        envelope--;
        envelope -= envelope >> 6;
      }
      else { // 6, 7: Linear increase.
        envelope += 0x20;
        if (mode > 6 && cast(uint) v.hiddenEnvelope > 0x600) {
          envelope += 0x8 - 0x20; // 7: Two-slope linear increase.
        }
      }
    }
  }

  // Sustain level.
  if ((envelope >> 8) == (envelopeData >> 5) && v.envelopeMode == EnvelopeDecay)
    v.envelopeMode = EnvelopeSustain;

  // Uint cast because linear decrease underflowing also triggers this.
  if (cast(uint) envelope > 0x4ff) {
    envelope = envelope < 0 ? 0 : 0x7ff;
    if (v.envelopeMode == EnvelopeAttack) v.envelopeMode = EnvelopeDecay;
  }

  if (counterPoll(rate)) v.envelope = envelope;
}

// BRR
// -------------------------------------------------------------------------------------------------

void brrDecode(ref Voice v) {
  // state._brrByte = smp.apuram[v.brrAddress + v.brrOffset] cached from previous clock cycle
  auto nybbles = (state._brrByte << 8) + smp.apuram[cast(ushort) (v.brrAddress + v.brrOffset + 1)];

  auto filter = (state._brrHeader >> 2) & 3;
  auto scale  = (state._brrHeader >> 4);

  // Decode four samples.
  foreach (n; 0..3) {
    // bits 12-15 = current nybble; sign extend, then shift right to 4-bit precision
    // result: s = 4-bit sign-extended sample value
    auto s = cast(short) nybbles >> 12;
    nybbles <<= 4; // slide nybble so that on next loop iteration, bits 12-15 = current nybble

    if (scale <= 12) {
      s <<= scale;
      s >>= 1;
    }
    else {
      s &= ~0x7ff;
    }

    // apply IIR filter (2 is the most commonly used)
    auto p1 = v.buffer[12 + v.bufferOffset - 1];
    auto p2 = v.buffer[12 + v.bufferOffset - 2] >> 1;

    final switch (filter) {
    case 0:
      break;

    case 1:
      // s += p1 * 0.46875
      s += p1 >> 1;
      s += (-p1) >> 5;
      break;

    case 2:
      // s += p1 * 0.953125 - p2 * 0.46875
      s += p1;
      s -= p2;
      s += p2 >> 4;
      s += (p1 * -3) >> 6;
      break;

    case 3:
      // s += p1 * 0.8984375 - p2 * 0.40625
      s += p1;
      s -= p2;
      s += (p1 * -13) >> 7;
      s += (p2 * 3) >> 4;
      break;
    }

    // Adjust and write sample (mirror the written sample for wrapping).
    s = cast(short) (s.sclamp!16 << 1);
    v.buffer[v.bufferOffset +  0] = s;
    v.buffer[v.bufferOffset + 12] = s;
    v.buffer[v.bufferOffset + 24] = s;
    if (++v.bufferOffset >= 12) v.bufferOffset = 0;
  }
}

// Misc.
// -------------------------------------------------------------------------------------------------

void misc27() {
  state._pmon = state.uregs[PMON] & ~1; // Voice 0 doesn't support PMON.
}

void misc28() {
  state._non = state.uregs[NON];
  state._eon = state.uregs[EON];
  state._dir = state.uregs[DIR];
}

void misc29() {
  state.everyOtherSample = !state.everyOtherSample;

  // Clears KON 63 clocks after it was last read.
  if (state.everyOtherSample) state.konBuffer &= ~state.kon;
}

void misc30() {
  if (state.everyOtherSample) {
    state.kon = state.konBuffer;
    state._koff = state.uregs[KOFF];
  }

  counterTick();

  // Noise.
  if (counterPoll(state.uregs[FLG] & 0x1f)) {
    auto feedback = (state.noise << 13) ^ (state.noise << 14);
    state.noise = (feedback & 0x4000) ^ (state.noise >> 1);
  }
}

// Voice
// -------------------------------------------------------------------------------------------------

void voiceOutput(ref Voice v, bool ch) {
  // Apply left/right volume.
  auto amp = (state._output * state.sregs[VOLL + ch]) >> 7;

  // Add to output total.
  state._mainOut[ch] += amp;
  state._mainOut[ch]  = state._mainOut[ch].sclamp!16;

  // Optionally add to echo total.
  if (state._eon & v.vbit) state._echoOut[ch] = (state._echoOut[ch] + amp).sclamp!16;
}

void voice1(ref Voice v) {
  state._dirAddress = (state._dir << 8) + (state._srcn << 2);
  state._srcn = v.reg(SRCN);
}

void voice2(ref Voice v) {
  // Read sample pointer (ignored if not needed).
  auto addr = state._dirAddress;
  if (v.konDelay == 0) addr += 2;
  auto lo = smp.apuram[cast(ushort) (addr + 0)];
  auto hi = smp.apuram[cast(ushort) (addr + 1)];
  state._brrNextAddress = (hi << 8) | lo;

  state._adsr0 = v.reg(ADSR0);
  state._pitch = v.reg(PITCHL); // Read pitch, spread over two clocks.
}

void voice3(ref Voice v) {
  v.voice3a();
  v.voice3b();
  v.voice3c();
}

void voice3a(ref Voice v) {
  state._pitch += (v.reg(PITCHH) & 0x3f) << 8;
}

void voice3b(ref Voice v) {
  state._brrHeader = smp.apuram[cast(ushort) (v.brrAddress)];
  state._brrByte   = smp.apuram[cast(ushort) (v.brrAddress + v.brrOffset)];
}

void voice3c(ref Voice v) {
  // Pitch Modulation using previous voice's output.
  if (state._pmon & v.vbit) state._pitch += ((state._output >> 5) * state._pitch) >> 10;
  if (v.konDelay != 0) {
    // Get ready to start BRR decoding on next sample.
    if (v.konDelay == 5) {
      v.brrAddress = state._brrNextAddress;
      v.brrOffset = 1;
      v.bufferOffset = 0;
      state._brrHeader = 0; // Header is ignored on this sample.
    }

    // Envelope is never run during KON.
    v.envelope = 0;
    v.hiddenEnvelope = 0;

    // Disable BRR decoding until last three samples.
    v.konDelay--;
    v.gaussianOffset = v.konDelay & 3 ? 0x4000 : 0;

    // Pitch is never added during KON.
    state._pitch = 0;
  }

  // Gaussian interpolation.
  auto output = v.gaussianInterpolate();

  // Noise.
  if (state._non & v.vbit) output = cast(short) (state.noise << 1);

  // Apply envelope.
  state._output = ((output * v.envelope) >> 11) & ~1;
  v._envxOut = v.envelope >> 4;

  // Immediate silence due to end of sample or soft reset.
  if (state.uregs[FLG] & 0x80 || (state._brrHeader & 3) == 1) {
    v.envelopeMode = EnvelopeRelease;
    v.envelope = 0;
  }

  if (state.everyOtherSample) {
    // KOFF
    if (state._koff & v.vbit) v.envelopeMode = EnvelopeRelease;

    // KON
    if (state.kon & v.vbit) {
      v.konDelay = 5;
      v.envelopeMode = EnvelopeAttack;
    }
  }

  // Run envelope for next sample.
  if (v.konDelay == 0) v.envelopeRun();
}

void voice4(ref Voice v) {
  // Decode BRR.
  state._looped = 0;
  if (v.gaussianOffset >= 0x4000) {
    v.brrDecode();
    v.brrOffset += 2;
    if (v.brrOffset >= 9) {
      // Start decoding next BRR block.
      v.brrAddress = cast(short) (v.brrAddress + 9);
      if (state._brrHeader & 1) {
        v.brrAddress = state._brrNextAddress;
        state._looped = v.vbit;
      }
      v.brrOffset = 1;
    }
  }

  // Apply pitch.
  v.gaussianOffset = (v.gaussianOffset & 0x3fff) + state._pitch;

  // Keep from getting too far ahead (when using pitch modulation).
  if (v.gaussianOffset > 0x7fff) v.gaussianOffset = 0x7fff;

  // Output left.
  voiceOutput(v, 0);
}

void voice5(ref Voice v) {
  // Output right.
  voiceOutput(v, 1);

  // ENDX, OUTX and ENVX won't update if written to 1-2 clocks earlier.
  state.endxBuffer = state.uregs[ENDX] | state._looped;

  // Clear bit in ENDX if KON just began.
  if (v.konDelay == 5) state.endxBuffer &= ~v.vbit;
}

void voice6(ref Voice v) {
  state.outxBuffer = state._output >> 8;
}

void voice7(ref Voice v) {
  state.uregs[ENDX] = cast(ubyte) state.endxBuffer;
  state.endxBuffer = v._envxOut;
}

void voice8(ref Voice v) {
  v.reg(OUTX) = cast(ubyte) state.outxBuffer;
}

void voice9(ref Voice v) {
  v.reg(ENVX) = cast(ubyte) state.envxBuffer;
}

// Echo
// -------------------------------------------------------------------------------------------------

int calculateFIR(bool ch, int index) {
  auto sample = state.echoHistory[ch][(state.echoHistoryOffset + index + 1).bits!3];
  return (sample * state.sregs[FIR + index * 0x10]) >> 6;
}

int echoOutput(bool ch) {
  return (cast(short) ((state._mainOut[ch] * state.sregs[MVOLL + ch * 0x10]) >> 7) +
          cast(short) ((state._echoIn [ch] * state.sregs[EVOLL + ch * 0x10]) >> 7)).sclamp!16;
}

void echoRead(bool ch) {
  auto addr = state._echoPointer + ch * 2;
  auto lo = smp.apuram[cast(ushort) (addr + 0)];
  auto hi = smp.apuram[cast(ushort) (addr + 1)];
  auto s = cast(ushort) ((hi << 8) + lo);
  state.echoHistory[ch][state.echoHistoryOffset] = s >> 1;
}

void echoWrite(bool ch) {
  if ((state._echoDisabled & 0x20) == 0) {
    auto addr = state._echoPointer + ch * 2;
    auto s = cast(ushort) state._echoOut[ch];
    smp.apuram[cast(ushort) (addr + 0)] = cast(ubyte) 0;
    smp.apuram[cast(ushort) (addr + 1)] = s >> 8;
  }
}

void echo22() {
  state.echoHistoryOffset = cast(ubyte) (state.echoHistoryOffset + 1).bits!3;
  state._echoPointer = cast(ushort) ((state._esa << 8) + state.echoOffset);
  echoRead(0);

  state._echoIn[0] = calculateFIR(0, 0);
  state._echoIn[1] = calculateFIR(1, 0);
}

void echo23() {
  state._echoIn[0] += calculateFIR(0, 1) + calculateFIR(0, 2);
  state._echoIn[1] += calculateFIR(1, 1) + calculateFIR(1, 2);
  echoRead(1);
}

void echo24() {
  state._echoIn[0] += calculateFIR(0, 3) + calculateFIR(0, 4) + calculateFIR(0, 5);
  state._echoIn[1] += calculateFIR(1, 3) + calculateFIR(1, 4) + calculateFIR(1, 5);
}

void echo25() {
  auto l = cast(short) (state._echoIn[0] + calculateFIR(0, 6)) + cast(short) calculateFIR(0, 7);
  auto r = cast(short) (state._echoIn[1] + calculateFIR(1, 6)) + cast(short) calculateFIR(1, 7);

  state._echoIn[0] = l.sclamp!16 & ~1;
  state._echoIn[1] = r.sclamp!16 & ~1;
}

void echo26() {
  // Left output volumes. Save sample for next clock so we can output both together.
  state._mainOut[0] = echoOutput(0);

  // Echo feedback.
  auto l = state._echoOut[0] + cast(short) ((state._echoIn[0] * state.sregs[EFB]) >> 7);
  auto r = state._echoOut[1] + cast(short) ((state._echoIn[1] * state.sregs[EFB]) >> 7);

  state._echoOut[0] = l.sclamp!16 & ~1;
  state._echoOut[1] = r.sclamp!16 & ~1;
}

void echo27() {
  // Output.
  auto outl = state._mainOut[0];
  auto outr = echoOutput(1);
  state._mainOut[0] = 0;
  state._mainOut[1] = 0;

  // TODO: global muting isn't this simple
  //(turns DAC on and off or something, causing small ~37-sample pulse when first muted)
  if (state.uregs[FLG] & 0x40) {
    outl = 0;
    outr = 0;
  }

  // Output sample to DAC.
  // TODO:
  // stream.sample(outl / 32768.0, outr / 32768.0);
}

void echo28() {
  state._echoDisabled = state.uregs[FLG];
}

void echo29() {
  state._esa = state.uregs[ESA];

  if (state.echoOffset == 0) state.echoLength = (state.uregs[EDL] & 0x0f) << 11;

  state.echoOffset += 4;
  if (state.echoOffset >= state.echoLength) state.echoOffset = 0;

  echoWrite(0); // Write left echo.

  state._echoDisabled = state.uregs[FLG];
}

void echo30() {
  echoWrite(1); // Write right echo.
}
