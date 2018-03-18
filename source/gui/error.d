/**
 * Displays a modal dialog after an exception is caught.
 */
module gui.error;

import std.algorithm : max, min;

import imgui;

import emulator.system : lastException;

import gui.icons;
import gui.fonts;
import gui.layout : fixedWindowFlags, ImGui_SetNextWindowPosCenter;

// TODO: use stack
private __gshared {
  string message; /// Formatted error message from the last exception.
  string stack;   /// Formatted stack trace from the last exception.
}

enum title = "Error!"; /// The title is also used to identify the error dialog.

/// Displays the error dialog as needed.
package void draw() {
  if (lastException !is null && !ImGui.IsPopupOpen(title)) {
    message = lastException.msg;
    stack   = lastException.toString();

    lastException = null;

    ImGui.OpenPopup(title);
  }

  auto size = ImVec2(min(max(ImGui.GetIO().DisplaySize.x / 3, 800), 400), -1);
  ImGui.SetNextWindowSize(size);
  ImGui_SetNextWindowPosCenter();
  ImGui.PushStyleVar(ImGuiStyleVar_WindowRounding, 0);

  if (ImGui.BeginPopupModal(title, null, fixedWindowFlags)) {
    show();

    ImGui.EndPopup();
  }

  ImGui.PopStyleVar();
}

private void show() nothrow @nogc {
  auto lineHeight = ImGui.GetItemsLineHeightWithSpacing();
  auto spacing    = ImVec2(1, lineHeight);

  // Header
  pushFont(Font.heading);
  auto red = cast(ImVec4) ImColor(0xd9, 0x53, 0x4f, 0xff);
  ImGui.TextColored(red, title);
  ImGui.Separator();

  // Content
  ImGui.Dummy(spacing);
  ImGui.Columns(2, null, false);
  ImGui.SetColumnWidth(0, 40);

  auto yellow = cast(ImVec4) ImColor(0xf0, 0xad, 0x4e, 0xff);
  ImGui.PushStyleColor(ImGuiCol_Text, yellow);
  ImGui.TextUnformatted(ICON_FA_EXCLAMATION_TRIANGLE);
  ImGui.PopStyleColor();
  ImGui.NextColumn();
  popFont();

  ImGui.TextUnformatted(message.ptr, message.ptr + message.length);
  ImGui.NextColumn();

  ImGui.Columns(1);
  ImGui.Dummy(spacing);

  // Footer
  pushFont(Font.large);
  auto size = ImVec2(-1, lineHeight);
  if (ImGui.Button("OK", size)) {
    message = stack = null;

    ImGui.CloseCurrentPopup();
  }
  popFont();
}
