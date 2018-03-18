/**
 * Displays a window allowing the user to tweak application settings.
 */
module gui.settings;

import imgui;

import emulator.util : Singleton, cstring;

import console  = emulator.console;
import platform = emulator.platform;

import gui.icons;
import gui.fonts;
import gui.layout : Window, isSingle;

private __gshared {
  cstring[] tabs = ["General", "Input", "Video", "Audio", "Misc"];
  uint activeTab;
  uint tabWidth = 100;
}

/// Makes the settings window visible.
void show(bool enable) {
  assert(SettingsWindow.instance);
  SettingsWindow.instance.show(enable);
}

/**
 * A window used to change the application's settings.
 *
 * The settings are stored in the application data directory when the window is
 * closed. They are instead reloaded if the user presses the cancel button.
 *
 * Settings are exposed through the console module. The window only generates
 * a view over registered settings.
 */
class SettingsWindow : Singleton!(SettingsWindow, Window, cstring) {
  this() {
    super("Settings");
    open = false;
  }

protected:
  override void preDraw() {
    ImGui.PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2_zero);
  }

  override void postDraw() {
    ImGui.PopStyleVar(1);
  }

  override void draw() {
    pushFont(Font.large);
    ImGui.PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2_zero);
    ImGui.BeginGroup();

    drawTabs();

    ImGui.EndGroup();
    ImGui.PopStyleVar(1);
    popFont();
    ImGui.SameLine();
    ImGui.BeginGroup();

    drawContent();

    ImGui.EndGroup();

    drawCloseButton();
  }

  override bool showInWindowMenu() const { return false; }

private:
  void show(bool enable) {
    open = enable;
    setActive();
  }

  void drawTabs() {
    auto size = ImVec2(tabWidth, 40);
    foreach (uint i, tab; tabs) {
      auto flags = i == activeTab ? ImGuiButtonFlags_Disabled : 0;
      ImGui.PushStyleVar(ImGuiStyleVar_Alpha, i == activeTab ? .5 : 1);

      if (ImGui.ButtonEx(tabs[i], size, flags)) {
        activeTab = i;
      }

      ImGui.PopStyleVar(1);
    }
  }

  void drawContent() {
    switch (activeTab) {
    case 0: ImGui.Text("a"); break;
    case 1: ImGui.Text("1"); break;
    case 2: ImGui.Text("2"); break;
    default: ImGui.Text("WUT");
    }
  }

  void drawCloseButton() {
    if (!isSingle) return;

    auto size = ImVec2(28, 28);
    auto pos = ImGui.GetIO().DisplaySize;
    pos.x -= size.x;
    pos.y = 0;

    ImGui.SetCursorPos(pos);
    pushFont(Font.large);
    if (ImGui.Button(ICON_FA_TIMES, size)) {
      open = false;
      restoreActive();
    }
    popFont();
  }
}
