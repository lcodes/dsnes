/**
 * Displays the output of the emulated system in a window.
 */
module gui.game;

import imgui;

import gui.layout : Window;

class GameWindow : Window {
  this() {
    super("Game".ptr);
  }

  protected override void draw() {
    ImGui.Image(cast(void*)1, ImVec2_zero);
  }
}
