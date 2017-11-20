module gui.game;

import imgui;

import emulator.gui : Window;

class GameWindow : Window {
  this() {
    super("Game".ptr);
  }

  protected override void draw() {
    ImGui.Image(cast(void*)1, ImVec2_zero);
  }
}
