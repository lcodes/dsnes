module gui.about;

import imgui;

import gui.common;

package:

__gshared bool show;

package void draw() {
  enum title = "About";

  if (show) {
    ImGui.OpenPopup(title);
    show = false;
  }

  auto size = ImVec2(400, 300);
  ImGui.SetNextWindowFocus();
  igSetNextWindowPosCenter();
  ImGui.SetNextWindowSize(size);
  ImGui.PushStyleVar(ImGuiStyleVar_WindowRounding, 0);

  enum windowFlags = ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
    ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoSavedSettings;

  if (ImGui.BeginPopupModal(title, null, windowFlags)) {
    ImGui.TextUnformatted("DSNES 1.0.0");
    ImGui.Separator();

    auto lineHeight = ImGui.GetItemsLineHeightWithSpacing();
    auto style = ImGui.GetStyle();

    size = ImVec2(0, -lineHeight - cast(int) style.ItemSpacing.y);
    ImGui.BeginChild("##About", size);
    ImGui.TextUnformatted("Hello world lorem ipsum...");
    ImGui.EndChild();

    size = ImVec2(-1, lineHeight);
    if (ImGui.Button("OK", size)) ImGui.CloseCurrentPopup();
    ImGui.EndPopup();
  }

  ImGui.PopStyleVar(1);
}
