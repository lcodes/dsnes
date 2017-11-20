module gui.settings;

import imgui;

import emulator.util : cstring;

import console = emulator.console;

import gui.common;

private __gshared {
  cstring[] tabs = ["General", "Input", "Video", "Audio", "Misc"];
  uint activeTab;
  uint tabWidth = 100;
}

package:

__gshared bool show;

void draw() {
  if (!show) return;

  auto windowMinSize = ImVec2(400, 300);

  ImGui.SetNextWindowFocus();
  igSetNextWindowPosCenter();
  ImGui.PushStyleVar(ImGuiStyleVar_WindowRounding, 0);
  ImGui.PushStyleVar(ImGuiStyleVar_WindowMinSize, windowMinSize);
  ImGui.PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2_zero);

  if (ImGui.Begin("Settings", &show, windowFlags)) {
    // Tabs
    ImGui.PushStyleVar(ImGuiStyleVar_ItemSpacing,  ImVec2_zero);
    ImGui.BeginGroup();
    auto size = ImVec2(tabWidth, 40);
    foreach (uint i, tab; tabs) {
      auto flags = i == activeTab ? ImGuiButtonFlags_Disabled : 0;
      ImGui.PushStyleVar(ImGuiStyleVar_Alpha, i == activeTab ? .5 : 1);
      if (ImGui.ButtonEx(tabs[i], size, flags)) activeTab = i;
      ImGui.PopStyleVar(1);
    }
    ImGui.EndGroup();
    ImGui.PopStyleVar(1);

    // Content
    ImGui.SameLine();
    ImGui.BeginGroup();
    switch (activeTab) {
    case 0: ImGui.Text("a"); break;
    case 1: ImGui.Text("1"); break;
    case 2: ImGui.Text("2"); break;
    default: ImGui.Text("WUT");
    }
    ImGui.EndGroup();

    ImGui.End();
  }

  ImGui.PopStyleVar(3);
}

private:

enum windowFlags = ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_AlwaysAutoResize |
  ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoSavedSettings;
