/**
 * Display information about the application.
 */
module gui.about;

import imgui;

import product = emulator.product;

import gui.fonts;
import gui.icons;
import gui.layout : fixedWindowFlags, ImGui_SetNextWindowPosCenter;

package:

__gshared bool show; /// Set to true to trigger opening the about popup.

enum title = "About";

/// Draws the about popup, opening it as needed.
package void draw() {
  if (show) {
    ImGui.OpenPopup(title);
    show = false;
  }

  auto size = ImVec2(400, 300);
  ImGui.SetNextWindowFocus();
  ImGui_SetNextWindowPosCenter();
  ImGui.SetNextWindowSize(size);
  ImGui.PushStyleVar(ImGuiStyleVar_WindowRounding, 0);

  if (ImGui.BeginPopupModal(title, null, fixedWindowFlags)) {
    // Header
    pushFont(Font.heading);
    ImGui.TextUnformatted(ICON_FA_GAMEPAD);
    ImGui.SameLine();
    ImGui.Text("%s v%s", product.name.ptr, product.versionString.ptr);
    ImGui.Separator();
    popFont();

    // Content
    auto style      = ImGui.GetStyle();
    auto lineHeight = ImGui.GetItemsLineHeightWithSpacing();
    auto spacing    = ImVec2(1, lineHeight);

    size = ImVec2(0, -lineHeight - cast(int) style.ItemSpacing.y);
    ImGui.BeginChild("##About", size);
    ImGui.Dummy(spacing);

    ImGui.TextUnformatted("Hello world lorem ipsum...");

    ImGui.Dummy(spacing);
    ImGui.EndChild();

    // Footer
    pushFont(Font.large);
    size = ImVec2(-1, lineHeight);
    if (ImGui.Button("OK", size)) {
      ImGui.CloseCurrentPopup();
    }
    popFont();

    ImGui.EndPopup();
  }

  ImGui.PopStyleVar(1);
}
