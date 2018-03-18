/**
 * References:
 * - https://github.com/pelrun/Dispel/blob/master/65816.c
 */
module disasm;

private {
  import core.stdc.stdio : sprintf;

  import std.bitmanip : bitfields;
  import std.conv : to;

  import cpu = snes.cpu;
  import mem = snes.memory;
}

enum AddressingMode : ubyte {
  implied,
  immediateMemoryFlag,
  immediateIndexFlag,
  immediate8Bit,
  relative,
  relativeLong,
  direct,
  directIndexedX,
  directIndexedY,
  directIndirect,
  directIndexedIndirect,
  directIndirectIndexed,
  directIndirectLong,
  directIndirectIndexedLong,
  absolute,
  absoluteIndexed,
  absoluteIndexedX,
  absoluteIndexedY,
  absoluteLong,
  absoluteIndexedLong,
  stackRelative,
  stackRelativeIndirectIndexed,
  absoluteIndirect,
  absoluteIndirectLong,
  absoluteIndirectIndirect,
  impliedAccumulator,
  blockMove
}

enum Mnemonic : ubyte {
  // Arithmetic & Logical
  ADC,
  SBC,
  AND,
  EOR,
  ORA,
  TSB,
  TRB,
  ASL,
  LSR,
  ROL,
  ROR,
  BIT,
  CMP,
  CPX,
  CPY,
  DEA,
  DEC,
  DEX,
  DEY,
  INA,
  INC,
  INX,
  INY,
  NOP,
  XBA,
  // Load/Store
  LDA,
  LDX,
  LDY,
  STA,
  STX,
  STY,
  STZ,
  // Transfer
  TAX,
  TAY,
  TCD,
  TCS,
  TDC,
  TSC,
  TSX,
  TSY,
  TXA,
  TXS,
  TXY,
  TYA,
  TYX,
  MVN,
  MVP,
  // Branch
  BCC,
  BCS,
  BNE,
  BEQ,
  BPL,
  BMI,
  BVC,
  BVS,
  BRA,
  BRL,
  // Jump and call
  JMP,
  JML,
  JSR,
  JSL,
  RTS,
  RTL,
  // Interrupt
  BRK,
  COP,
  RTI,
  STP,
  WAI,
  // P Flag
  CLC,
  CLD,
  CLI,
  CLV,
  REP,
  SEC,
  SED,
  SEP,
  SEI,
  XCE,
  // Stack
  PHA,
  PHX,
  PHY,
  PHD,
  PHB,
  PHK,
  PHP,
  PEA,
  PEI,
  PER,
  PLA,
  PLX,
  PLY,
  PLP,
  PLD,
  PLB,
  // Reserved
  WDM
}

struct Instruction {
  ubyte id;
  ubyte[3] b;
  AddressingMode mode;
  cpu.Flags flagsSet;

  mixin(bitfields!(ubyte, "bytes",  4,
                   ubyte, "cycles", 4));
}

/**
 * String Format:
 *   "$BB:AAAA    MMM OOOOOOOOOO    CC CC CC CC "
 *
 *   B: Bank
 *   A: Address
 *   M: Mnemonic
 *   O: Operands
 *   C: Code
 */
char[] disasm(ref uint addr, char[] text) {
  enum Offset {
    addr = 0,
    mnemonic = 12,
    operands = 16,
    code = 30,
    end = 42
  }

  assert(text.length >= Offset.end);
  sprintf(text.ptr + Offset.addr, "$%02x:%04x    ", addr >> 16, addr & ushort.max);

  auto op = mem.read(addr);
  auto pf = cpu.registers.p;

  Mnemonic m;
  final switch (op) with (Mnemonic) {
  case 0x69:
  case 0x6D:
  case 0x6F:
  case 0x65:
  case 0x72:
  case 0x67:
  case 0x7D:
  case 0x7F:
  case 0x79:
  case 0x75:
  case 0x61:
  case 0x71:
  case 0x77:
  case 0x63:
  case 0x73: m = ADC; break;
  case 0x29:
  case 0x2D:
  case 0x2F:
  case 0x25:
  case 0x32:
  case 0x27:
  case 0x3D:
  case 0x3F:
  case 0x39:
  case 0x35:
  case 0x21:
  case 0x31:
  case 0x37:
  case 0x23:
  case 0x33: m = AND; break;
  case 0x0A:
  case 0x0E:
  case 0x06:
  case 0x1E:
  case 0x16: m = ASL; break;
  case 0x90: m = BCC; break;
  case 0xB0: m = BCS; break;
  case 0xF0: m = BEQ; break;
  case 0xD0: m = BNE; break;
  case 0x30: m = BMI; break;
  case 0x10: m = BPL; break;
  case 0x50: m = BVC; break;
  case 0x70: m = BVS; break;
  case 0x80: m = BRA; break;
  case 0x82: m = BRL; break;
  case 0x89:
  case 0x2C:
  case 0x24:
  case 0x3C:
  case 0x34: m = BIT; break;
  case 0x00: m = BRK; break;
  case 0x18: m = CLC; break;
  case 0xD8: m = CLD; break;
  case 0x58: m = CLI; break;
  case 0xB8: m = CLV; break;
  case 0x38: m = SEC; break;
  case 0xF8: m = SED; break;
  case 0x78: m = SEI; break;
  case 0xC9:
  case 0xCD:
  case 0xCF:
  case 0xC5:
  case 0xD2:
  case 0xC7:
  case 0xDD:
  case 0xDF:
  case 0xD9:
  case 0xD5:
  case 0xC1:
  case 0xD1:
  case 0xD7:
  case 0xC3:
  case 0xD3: m = CMP; break;
  case 0x02: m = COP; break;
  case 0xE0:
  case 0xEC:
  case 0xE4: m = CPX; break;
  case 0xC0:
  case 0xCC:
  case 0xC4: m = CPY; break;
  case 0x3A:
  case 0xCE:
  case 0xC6:
  case 0xDE:
  case 0xD6: m = DEC; break;
  case 0xCA: m = DEX; break;
  case 0x88: m = DEY; break;
  case 0x49:
  case 0x4D:
  case 0x4F:
  case 0x45:
  case 0x52:
  case 0x47:
  case 0x5D:
  case 0x5F:
  case 0x59:
  case 0x55:
  case 0x41:
  case 0x51:
  case 0x57:
  case 0x43:
  case 0x53: m = EOR; break;
  case 0x1A:
  case 0xEE:
  case 0xE6:
  case 0xFE:
  case 0xF6: m = INC; break;
  case 0xE8: m = INX; break;
  case 0xC8: m = INY; break;
  case 0x4C:
  case 0x6C:
  case 0x7C:
  case 0x5C:
  case 0xDC: m = JMP; break;
  case 0x22:
  case 0x20:
  case 0xFC: m = JSR; break;
  case 0xA9:
  case 0xAD:
  case 0xAF:
  case 0xA5:
  case 0xB2:
  case 0xA7:
  case 0xBD:
  case 0xBF:
  case 0xB9:
  case 0xB5:
  case 0xA1:
  case 0xB1:
  case 0xB7:
  case 0xA3:
  case 0xB3: m = LDA; break;
  case 0xA2:
  case 0xAE:
  case 0xA6:
  case 0xBE:
  case 0xB6: m = LDX; break;
  case 0xA0:
  case 0xAC:
  case 0xA4:
  case 0xBC:
  case 0xB4: m = LDY; break;
  case 0x4A:
  case 0x4E:
  case 0x46:
  case 0x5E:
  case 0x56: m = LSR; break;
  case 0x54: m = MVN; break;
  case 0x44: m = MVP; break;
  case 0xEA: m = NOP; break;
  case 0x09:
  case 0x0D:
  case 0x0F:
  case 0x05:
  case 0x12:
  case 0x07:
  case 0x1D:
  case 0x1F:
  case 0x19:
  case 0x15:
  case 0x01:
  case 0x11:
  case 0x17:
  case 0x03:
  case 0x13: m = ORA; break;
  case 0xF4: m = PEA; break;
  case 0xD4: m = PEI; break;
  case 0x62: m = PER; break;
  case 0x48: m = PHA; break;
  case 0x08: m = PHP; break;
  case 0xDA: m = PHX; break;
  case 0x5A: m = PHY; break;
  case 0x68: m = PLA; break;
  case 0x28: m = PLP; break;
  case 0xFA: m = PLX; break;
  case 0x7A: m = PLY; break;
  case 0x8B: m = PHB; break;
  case 0x0B: m = PHD; break;
  case 0x4B: m = PHK; break;
  case 0xAB: m = PLB; break;
  case 0x2B: m = PLD; break;
  case 0xC2: m = REP; break;
  case 0x2A:
  case 0x2E:
  case 0x26:
  case 0x3E:
  case 0x36: m = ROL; break;
  case 0x6A:
  case 0x6E:
  case 0x66:
  case 0x7E:
  case 0x76: m = ROR; break;
  case 0x40: m = RTI;
    // if(tsrc&0x2)
    //   strcat(ibuf,"\n");
    break;
  case 0x6B: m = RTL;
    // if(tsrc&0x2)
    //   strcat(ibuf,"\n");
    break;
  case 0x60: m = RTS;
    // if(tsrc&0x2)
    //   strcat(ibuf,"\n");
    break;
  case 0xE9:
  case 0xED:
  case 0xEF:
  case 0xE5:
  case 0xF2:
  case 0xE7:
  case 0xFD:
  case 0xFF:
  case 0xF9:
  case 0xF5:
  case 0xE1:
  case 0xF1:
  case 0xF7:
  case 0xE3:
  case 0xF3: m = SBC; break;
  case 0xE2: m = SEP; break;
  case 0x8D:
  case 0x8F:
  case 0x85:
  case 0x92:
  case 0x87:
  case 0x9D:
  case 0x9F:
  case 0x99:
  case 0x95:
  case 0x81:
  case 0x91:
  case 0x97:
  case 0x83:
  case 0x93: m = STA; break;
  case 0xDB: m = STP; break;
  case 0x8E:
  case 0x86:
  case 0x96: m = STX; break;
  case 0x8C:
  case 0x84:
  case 0x94: m = STY; break;
  case 0x9C:
  case 0x64:
  case 0x9E:
  case 0x74: m = STZ; break;
  case 0xAA: m = TAX; break;
  case 0xA8: m = TAY; break;
  case 0x8A: m = TXA; break;
  case 0x98: m = TYA; break;
  case 0xBA: m = TSX; break;
  case 0x9A: m = TXS; break;
  case 0x9B: m = TXY; break;
  case 0xBB: m = TYX; break;
  case 0x5B: m = TCD; break;
  case 0x7B: m = TDC; break;
  case 0x1B: m = TCS; break;
  case 0x3B: m = TSC; break;
  case 0x1C:
  case 0x14: m = TRB; break;
  case 0x0C:
  case 0x04: m = TSB; break;
  case 0xCB: m = WAI; break;
  case 0x42: m = WDM; break;
  case 0xEB: m = XBA; break;
  case 0xFB: m = XCE; break;
  }

  auto p = cast(uint) Offset.mnemonic;
  text[p + 0 .. p + 3] = m.to!string;
  text[p + 3] = ' ';

  auto pbuf = text.ptr + Offset.operands;

  uint s;
  final switch (op) {
  // Absolute
  case 0x0C:
  case 0x0D:
  case 0x0E:
  case 0x1C:
  case 0x20:
  case 0x2C:
  case 0x2D:
  case 0x2E:
  case 0x4C:
  case 0x4D:
  case 0x4E:
  case 0x6D:
  case 0x6E:
  case 0x8C:
  case 0x8D:
  case 0x8E:
  case 0x9C:
  case 0xAC:
  case 0xAD:
  case 0xAE:
  case 0xCC:
  case 0xCD:
  case 0xCE:
  case 0xEC:
  case 0xED:
  case 0xEE:
    p = sprintf(pbuf, "$%04X", read16(addr));
    s = 3;
    break;
  // Absolute Indexed Indirect
  case 0x7C:
  case 0xFC:
    p = sprintf(pbuf, "($%04X,X)", read16(addr));
    s = 3;
    break;
  // Absolute Indexed, X
  case 0x1D:
  case 0x1E:
  case 0x3C:
  case 0x3D:
  case 0x3E:
  case 0x5D:
  case 0x5E:
  case 0x7D:
  case 0x7E:
  case 0x9D:
  case 0x9E:
  case 0xBC:
  case 0xBD:
  case 0xDD:
  case 0xDE:
  case 0xFD:
  case 0xFE:
    p = sprintf(pbuf, "$%04X,X", read16(addr));
    s = 3;
    break;
  // Absolute Indexed, Y
  case 0x19:
  case 0x39:
  case 0x59:
  case 0x79:
  case 0x99:
  case 0xB9:
  case 0xBE:
  case 0xD9:
  case 0xF9:
    p = sprintf(pbuf, "$%04X,Y", read16(addr));
    s = 3;
    break;
  // Absolute Indirect
  case 0x6C:
    p = sprintf(pbuf, "($%04X)", read16(addr));
    s = 3;
    break;
  // Absolute Indirect Long
  case 0xDC:
    p = sprintf(pbuf, "[$%04X]", read16(addr));
    s = 3;
    break;
  // Absolute Long
  case 0x0F:
  case 0x22:
  case 0x2F:
  case 0x4F:
  case 0x5C:
  case 0x6F:
  case 0x8F:
  case 0xAF:
  case 0xCF:
  case 0xEF:
    p = sprintf(pbuf, "$%06X", read24(addr));
    s = 4;
    break;
  // Absolute Long Indexed, X
  case 0x1F:
  case 0x3F:
  case 0x5F:
  case 0x7F:
  case 0x9F:
  case 0xBF:
  case 0xDF:
  case 0xFF:
    p = sprintf(pbuf, "$%06X,X", read24(addr));
    s = 4;
    break;
  // Accumulator
  case 0x0A:
  case 0x1A:
  case 0x2A:
  case 0x3A:
  case 0x4A:
  case 0x6A:
    p = sprintf(pbuf, "A");
    s = 1;
    break;
  // Block Move
  case 0x44:
  case 0x54:
    p = sprintf(pbuf, "$%02X,$%02X", mem.read(addr + 1), mem.read(addr + 2));
    s = 3;
    break;
  // Direct Page
  case 0x04:
  case 0x05:
  case 0x06:
  case 0x14:
  case 0x24:
  case 0x25:
  case 0x26:
  case 0x45:
  case 0x46:
  case 0x64:
  case 0x65:
  case 0x66:
  case 0x84:
  case 0x85:
  case 0x86:
  case 0xA4:
  case 0xA5:
  case 0xA6:
  case 0xC4:
  case 0xC5:
  case 0xC6:
  case 0xE4:
  case 0xE5:
  case 0xE6:
    p = sprintf(pbuf, "$%02X", mem.read(addr + 1));
    s = 2;
    break;
  // Direct Page Indexed, X
  case 0x15:
  case 0x16:
  case 0x34:
  case 0x35:
  case 0x36:
  case 0x55:
  case 0x56:
  case 0x74:
  case 0x75:
  case 0x76:
  case 0x94:
  case 0x95:
  case 0xB4:
  case 0xB5:
  case 0xD5:
  case 0xD6:
  case 0xF5:
  case 0xF6:
    p = sprintf(pbuf, "$%02X,X", mem.read(addr + 1));
    s = 2;
    break;
  // Direct Page Indexed, Y
  case 0x96:
  case 0xB6:
    p = sprintf(pbuf, "$%02X,Y", mem.read(addr + 1));
    s = 2;
    break;
  // Direct Page Indirect
  case 0x12:
  case 0x32:
  case 0x52:
  case 0x72:
  case 0x92:
  case 0xB2:
  case 0xD2:
  case 0xF2:
    p = sprintf(pbuf, "($%02X)", mem.read(addr + 1));
    s = 2;
    break;
  // Direct Page Indirect Long
  case 0x07:
  case 0x27:
  case 0x47:
  case 0x67:
  case 0x87:
  case 0xA7:
  case 0xC7:
  case 0xE7:
    p = sprintf(pbuf, "[$%02X]", mem.read(addr + 1));
    s = 2;
    break;
  // Direct Page Indexed Indirect, X
  case 0x01:
  case 0x21:
  case 0x41:
  case 0x61:
  case 0x81:
  case 0xA1:
  case 0xC1:
  case 0xE1:
    p = sprintf(pbuf, "($%02X,X)", mem.read(addr + 1));
    s = 2;
    break;
  // Direct Page Indirect Indexed, Y
  case 0x11:
  case 0x31:
  case 0x51:
  case 0x71:
  case 0x91:
  case 0xB1:
  case 0xD1:
  case 0xF1:
    p = sprintf(pbuf, "($%02X),Y", mem.read(addr + 1));
    s = 2;
    break;
  // Direct Page Indirect Long Indexed, Y
  case 0x17:
  case 0x37:
  case 0x57:
  case 0x77:
  case 0x97:
  case 0xB7:
  case 0xD7:
  case 0xF7:
    p = sprintf(pbuf, "[$%02X],Y", mem.read(addr + 1));
    s = 2;
    break;
  // Stack (Pull)
  case 0x28:
  case 0x2B:
  case 0x68:
  case 0x7A:
  case 0xAB:
  case 0xFA:
  // Stack (Push)
  case 0x08:
  case 0x0B:
  case 0x48:
  case 0x4B:
  case 0x5A:
  case 0x8B:
  case 0xDA:
  // Stack (RTL)
  case 0x6B:
  // Stack (RTS)
  case 0x60:
  // Stack/RTI
  case 0x40:
  // Implied
  case 0x18:
  case 0x1B:
  case 0x38:
  case 0x3B:
  case 0x58:
  case 0x5B:
  case 0x78:
  case 0x7B:
  case 0x88:
  case 0x8A:
  case 0x98:
  case 0x9A:
  case 0x9B:
  case 0xA8:
  case 0xAA:
  case 0xB8:
  case 0xBA:
  case 0xBB:
  case 0xC8:
  case 0xCA:
  case 0xCB:
  case 0xD8:
  case 0xDB:
  case 0xE8:
  case 0xEA:
  case 0xEB:
  case 0xF8:
  case 0xFB:
    p = 0;
    s = 1;
    break;
  // Program Counter Relative
  case 0x10:
  case 0x30:
  case 0x50:
  case 0x70:
  case 0x80:
  case 0x90:
  case 0xB0:
  case 0xD0:
  case 0xF0:
    // Calculate the signed value of the param
    auto sval = cast(int) mem.read(addr + 1);
    sval = sval > byte.max ? sval - ubyte.max : sval;
    p = sprintf(pbuf, "$%04lX", (addr + sval + 2) & 0xffff);
    s = 2;
    break;
  // Stack (Program Counter Relative Long)
  case 0x62:
  // Program Counter Relative Long
  case 0x82:
    // Calculate the signed value of the param
    auto sval = cast(int) read16(addr);
    sval = sval > short.max ? sval - ushort.max : sval;
    p = sprintf(pbuf, "$%04lX", (addr + sval + 3) & 0xFFFF);
    s = 3;
    break;
  // Stack Relative Indirect Indexed, Y
  case 0x13:
  case 0x33:
  case 0x53:
  case 0x73:
  case 0x93:
  case 0xB3:
  case 0xD3:
  case 0xF3:
    p = sprintf(pbuf, "($%02X,S),Y", mem.read(addr + 1));
    s = 2;
    break;
  // Stack (Absolute)
  case 0xF4:
    p = sprintf(pbuf, "$%04X", read16(addr));
    s = 3;
    break;
  // Stack (Direct Page Indirect)
  case 0xD4:
    p = sprintf(pbuf, "($%02X)", mem.read(addr + 1));
    s = 2;
    break;
  // Stack Relative
  case 0x03:
  case 0x23:
  case 0x43:
  case 0x63:
  case 0x83:
  case 0xA3:
  case 0xC3:
  case 0xE3:
    p = sprintf(pbuf, "$%02X,S", mem.read(addr + 1));
    s = 2;
    break;
  // WDM mode
  case 0x42:
  // Stack/Interrupt
  case 0x00:
  case 0x02:
    p = sprintf(pbuf, "$%02X", mem.read(addr + 1));
    s = 2;
    break;
  // Immediate (Invariant)
  case 0xC2:
    // REP following
    // *flag=*flag&~mem[1];
    p = sprintf(pbuf, "#$%02X", mem.read(addr + 1));
    s = 2;
    break;
  case 0xE2:
    // SEP following
    // *flag = *flag|mem[1];
    p = sprintf(pbuf, "#$%02X", mem.read(addr + 1));
    s = 2;
    break;
  // Immediate (A size dependent)
  case 0x09:
  case 0x29:
  case 0x49:
  case 0x69:
  case 0x89:
  case 0xA9:
  case 0xC9:
  case 0xE9:
    if (pf.m) {
      p = sprintf(pbuf, "#$%02X", mem.read(addr + 1));
      s = 2;
    }
    else {
      p = sprintf(pbuf, "#$%04X", read16(addr));
      s = 3;
    }
    break;
  // Immediate (X/Y size dependent)
  case 0xA0:
  case 0xA2:
  case 0xC0:
  case 0xE0:
    if (pf.x) {
      p = sprintf(pbuf, "#$%02X", mem.read(addr + 1));
      s = 2;
    }
    else {
      p = sprintf(pbuf, "#$%04X", read16(addr));
      s = 3;
    }
    break;
  }

  text[Offset.operands + p .. Offset.code] = ' ';

  pbuf = text.ptr + Offset.code;

  foreach (n; 0..s) {
    pbuf += sprintf(pbuf, "%02x", mem.read(addr + n));

    pbuf[0] = ' ';
    pbuf += 1;
  }

  foreach (n; s..4) {
    pbuf[0 .. 3] = ' ';
    pbuf += 3;
  }

  auto result = text[0..Offset.end];
  assert(pbuf is text.ptr + Offset.end, result);

  addr += s;

  return result;
}

uint read16(uint addr) {
  return mem.read(addr + 1) | (mem.read(addr + 2) << 8);
}

uint read24(uint addr) {
  return read16(addr) | (mem.read(addr + 3) << 16);
}
