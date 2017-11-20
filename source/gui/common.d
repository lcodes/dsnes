module gui.common;

import imgui;

immutable pivotCenter = ImVec2(0.5, 0.5);

void igSetNextWindowPosCenter(ImGuiCond cond = 0) {
  auto io = &ImGui.GetIO();
  auto pos = ImVec2(io.DisplaySize.x * 0.5,
                    io.DisplaySize.y * 0.5f);
  ImGui.SetNextWindowPos(pos, cond, pivotCenter);
}
