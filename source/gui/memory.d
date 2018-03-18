/**
 * References:
 *   https://github.com/ocornut/imgui/wiki/memory_editor_example
 */
module gui.memory;

import core.stdc.stdio : sscanf;

import imgui;

import gui.layout : Window;

class MemoryWindow : Window {
  private {
    // R read;
    // W write;
    uint size;
    uint rows = 16;
    uint baseDisplayAddr = 0;
    uint dataEditingAddr = -1;
    uint addrDigitsCount = 6;
    bool allowEdits;
  }

  // alias R = ubyte function(uint addr);
  // alias W = void function(uint addr, ubyte data);

  this() {
    super("Memory".ptr);
  }

  bool a = true;

  protected override void draw() {
    auto childSize = ImVec2(0, -ImGui.GetItemsLineHeightWithSpacing());
    ImGui.BeginChild("##scrolling", childSize);

    ImGui.PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2_zero);
    ImGui.PushStyleVar(ImGuiStyleVar_ItemSpacing,  ImVec2_zero);

    ImVec2 v = ImGui.CalcTextSize("F");
    auto glyphWidth = v.x;
    auto cellWidth = glyphWidth * 3;

    auto lineHeight = ImGui.GetTextLineHeight();
    auto lineCount  = (size + rows - 1) / rows;
    auto clipper    = ImGuiListClipper(lineCount, lineHeight);
    auto startAddr  = clipper.DisplayStart * rows;
    auto endAddr    = clipper.DisplayEnd   * rows;

    if (!allowEdits || dataEditingAddr >= size) dataEditingAddr = -1;

    auto dataNext = false;
    auto editBackup = dataEditingAddr;
    if (dataEditingAddr != -1) {
      // TODO
    }

    // Track cursor movement
    auto newPage = dataEditingAddr / rows;
    auto oldPage = editBackup     / rows;
    if (newPage != oldPage) {
      auto scrollOffset = newPage - oldPage;
      auto scrollDesired =
        (scrollOffset < 0 && dataEditingAddr < startAddr + rows * 2) ||
        (scrollOffset > 0 && dataEditingAddr > endAddr   - rows * 2);

      if (scrollDesired) ImGui.SetScrollY(cast(int) (ImGui.GetScrollY() + scrollOffset));
    }

    auto drawSeparator = true;
    foreach (line; clipper.DisplayStart .. clipper.DisplayEnd) {
      auto addr = line * rows;
      ImGui.Text("%0*X: ", addrDigitsCount, baseDisplayAddr + addr);
      ImGui.SameLine();

      auto lineStartX = ImGui.GetCursorPosX();
      for (auto n = 0; n < rows && addr < size; n++, addr++) {
        ImGui.SameLine(lineStartX + cellWidth * n);

        if (dataEditingAddr == addr) {
          // TODO
        }
        else {
          auto x = 0; //read(addr);
          ImGui.Text("%02X ", x);
          if (allowEdits && ImGui.IsItemHovered() && ImGui.IsMouseClicked(0)) {
            // dataEditingTakeFocus = true;
            dataEditingAddr = addr;
          }
        }
      }

      ImGui.SameLine(lineStartX + cellWidth * rows + glyphWidth * 2);

      // if (drawSeparator) {
      //   ImVec2 screenPos = void;
      //   ImGui.GetCursorScreenPos(&screenPos);
      //   ImGui.GetWindowDrawList().ImDrawList_AddLine(ImVec2(screenPos.x - glyphWidth, screenPos.y - 9999),
      //                                            ImVec2(screenPos.x - glyphWidth, screenPos.y + 9999),
      //                                            ImColor(ImGui.GetStyle().Colors[ImGuiCol_Border]));
      //   drawSeparator = false;
      // }

      // ASCII values
      addr = line * rows;
      for (auto n = 0; n < rows && addr < size; n++, addr++) {
        if (n > 0) ImGui.SameLine();
        // auto c = cast(char) read(addr);
        auto c = '.';
        ImGui.Text("%c", c >= 32 && c < 128 ? c : '.');
      }
    }

    clipper.End();
    ImGui.PopStyleVar(2);

    ImGui.EndChild();

    if (dataNext && dataEditingAddr < size) {
      dataEditingAddr = dataEditingAddr + 1;
      // dataEditingTakeFocus = true;
    }

    ImGui.Separator();

    ImGui.AlignTextToFramePadding();
    ImGui.PushItemWidth(50);
    ImGui.PushAllowKeyboardFocus(false);
    // auto rowsBackup = rows;
    // if ()
    ImGui.Text("Range %0*x..%0*x", addrDigitsCount, baseDisplayAddr, addrDigitsCount, baseDisplayAddr + size - 1);
    ImGui.SameLine();
    ImGui.PushItemWidth(70);
    auto addrInputFlag = ImGuiInputTextFlags_CharsHexadecimal | ImGuiInputTextFlags_EnterReturnsTrue;
    char[32] addrInput = void;
    if (ImGui.InputText("##addr", addrInput.ptr, addrInput.length, addrInputFlag)) {
      int gotoAddr;
      if (sscanf(addrInput.ptr, "%x", &gotoAddr) == 1) {
        ImGui.BeginChild("##scrolling");
        ImVec2 cursorStartPos = ImGui.GetCursorStartPos();
        ImGui.SetScrollFromPosY(cursorStartPos.y + (gotoAddr / rows) * lineHeight);
        ImGui.EndChild();
      }
    }
    ImGui.PopItemWidth();
  }
}
