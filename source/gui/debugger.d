module gui.debugger;

import imgui;

import thread = emulator.thread;

import gui.icons;

// TODO: toolbar
version(none)
class DebuggerWindow : Window {
  this() {
    super("Debugger".ptr);
    windowFlags = ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize;
  }

  protected override void draw() {
    import console = emulator.console;

    auto isRunning = !thread.isPaused;
    auto flags = isRunning ? ImGuiButtonFlags_Disabled : 0;

    if (isRunning) {
      if (ImGui.Button(ICON_FA_PAUSE)) thread.dbgBreak();
      tooltip("Break");
    }
    else {
      if (ImGui.Button(ICON_FA_PLAY)) thread.dbgContinue();
      tooltip("Continue");
    }

    ImGui.PushStyleVar(ImGuiStyleVar_Alpha, isRunning ? .25 : 1);

    ImGui.SameLine();
    if (ImGui.ButtonEx(ICON_FA_CHEVRON_RIGHT, ImVec2_zero, flags)) {
      console.info("Step");
    }
    tooltip("Step");
    ImGui.SameLine();

    if (ImGui.ButtonEx(ICON_FA_CHEVRON_DOWN, ImVec2_zero, flags)) {
      console.info("Step Into");
    }
    tooltip("Step Into");
    ImGui.SameLine();

    if (ImGui.ButtonEx(ICON_FA_CHEVRON_UP, ImVec2_zero, flags)) {
      console.info("Step Out");
    }
    tooltip("Step Out");
    ImGui.SameLine();

    if (ImGui.ButtonEx(ICON_FA_ARROW_RIGHT, ImVec2_zero, flags)) {
      console.info("Run to Cursor");
    }
    tooltip("Run to Cursor");
    ImGui.SameLine();

    if (ImGui.ButtonEx(ICON_FA_REFRESH, ImVec2_zero, flags)) {
      console.info("WHOA");
    }
    tooltip("Run to Next Frame");

  //   ImGui.Separator();
  //   ImGui.BeginChild("##scrolling", ImVec2(0, -ImGui.GetItemsLineHeImGui.htWithSpacing()));
  //   auto clipper = ImGuiListClipper(0, 10);

  //   foreach (n; clipper.DisplayStart .. clipper.DisplayEnd) {
  //     ImGui.Text("BRK");
  //   }

  //   clipper.End();
  //   ImGui.EndChild();

  //   ImGui.Separator();
  //   ImGui.Text("%u breakpoints", 0);

    ImGui.PopStyleVar(1);
  }
}
