module emulator.types;

alias Reg8 = ubyte;

union Reg16 {
  ushort w; alias w this;
  struct { ubyte l, h; }

  ref ubyte opIndex(bool i) nothrow @nogc {
    return i ? h : l;
  }

  private unittest {
    assert(Reg16(0xff00).h == 0xff);
  }
}

union Reg24 {
  uint d; alias d this;
  struct { ushort w, wh; }
  struct { ubyte l, h, b, bh; }

  private unittest {
    assert(Reg24(0xff_dead).b == 0xff);
    assert(Reg24(0xff_face).w == 0xface);
  }
}

static assert(Reg8 .sizeof == 1);
static assert(Reg16.sizeof == 2);
static assert(Reg24.sizeof == 4);
