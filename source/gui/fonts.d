/**
 * GUI fonts.
 */
module gui.fonts;

import imgui;

enum Font {
  normal,
  large,
  heading,
  code
}

__gshared {
  ImFont*[Font.max + 1] fonts;
  private ImFont* scaled;
}

nothrow @nogc:

void pushFont(Font font) {
  ImGui.PushFont(fonts[font]);
}

alias popFont = ImGui.PopFont;

void pushFontScale(Font font, float scale) {
  scaled = fonts[font];
  scaled.Scale = scale;
  ImGui.PushFont(scaled);
}

void popFontScale() {
  popFont();
  scaled.Scale = 1;
  scaled = null;
}
