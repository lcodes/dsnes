module gui.status;

import imgui;

import pak = snes.cartridge;

package void draw() {
  enum windowFlags = ImGuiWindowFlags_NoTitleBar |
    ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoMove |
    ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoSavedSettings;

  auto io = &ImGui.GetIO();
  auto height = ImGui.GetItemsLineHeightWithSpacing();
  auto pos = ImVec2(0, io.DisplaySize.y - height);
  auto size = ImVec2(io.DisplaySize.x, height);
  auto windowBg = ImVec4(0, 0, 0, .25);
  ImGui.SetNextWindowPos(pos);
  ImGui.SetNextWindowSize(size);
  ImGui.PushStyleVar(ImGuiStyleVar_WindowMinSize, ImVec2_zero);
  ImGui.PushStyleVar(ImGuiStyleVar_WindowRounding, 0);
  ImGui.PushStyleColor(ImGuiCol_WindowBg, windowBg);

  auto result = ImGui.Begin("##MainStatusBar", null, windowFlags);
  assert(result);

  ImGui.Text("Hello!");

  ImGui.End();
  ImGui.PopStyleColor(1);
  ImGui.PopStyleVar(2);
}
