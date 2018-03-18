/**
 * Displays the collected profiling data.
 *
 * Defines nothing if profiling is disabled.
 */
module gui.profiler;

import profiler = emulator.profiler;

static if (profiler.enabled):

import core.stdc.stdio : snprintf;

import std.algorithm : max, min;

import imgui;

import emulator.util : cstring;

import gui.layout : Window;

/**
 *
 */
class ProfilerWindow : Window {
  enum : float {
    splitRatio = 3,
    leftColumnWidth = 150
  }

  private {
    uint showThreadBits = uint.max; /// Bitfield of shown thread profiles.
  }

  this() {
    super("Profiler".ptr);
  }

// nothrow @nogc:

  protected override void draw() {
    auto style   = &ImGui.GetStyle();
    auto padding = style.WindowPadding.y;
    auto avail   = ImGui.GetWindowHeight() - ImGui.GetCursorPosY() - padding;
    auto size    = ImVec2(-1, min(avail / splitRatio, 250));

    ImGui.BeginChild("timelines", size);
    drawTimelines();
    ImGui.EndChild();

    auto headerSize = ImVec2(-1, ImGui.GetItemsLineHeightWithSpacing());
    ImGui.BeginChild("detailsHeader", headerSize);
    drawDetailsHeader();
    ImGui.EndChild();

    size.y = avail - size.y - headerSize.y - style.ItemSpacing.y;
    ImGui.BeginChild("details", size);
    drawDetails();
    ImGui.EndChild();
  }

private:

  void drawMenuBar() {
    if (ImGui.MenuItem("View")) {
    }
  }

  void drawTimelines() {
    foreach (n; 0..100)
    ImGui.Text("TIMELINE");
  }

  void drawDetailsHeader() {
    // auto pos = ImGui.GetCursorPosY();
    // auto spc = ImGui.GetTextLineHeightWithSpacing();

    // auto bg = ImGui.GetColorU32(ImGuiCol_MenuBarBg);
    // auto p0 = ImVec2(0, pos + spc);
    // auto p1 = ImVec2(ImGui.GetWindowWidth(), spc + 2) + p0;
    // ImGui.GetWindowDrawList().AddRectFilled(p0, p1, bg);

    ImGui.Text("DETAILS MENU");
    ImGui.SameLine();

    // ImGui.SetCursorPosY(ImGui.GetCursorPosY() - 2);

    if (ImGui.Button("View")) {
    }
  }

  void drawDetails() {
    foreach (idx, ref const thread; threads) {
      if (idx != 0) {
        // ImGui.Separator();
      }

      if (thread.show) {
        ImGui.Columns(2, null, ImGuiColumnsFlags_NoBorder);
        ImGui.SetColumnWidth(0, 200);

        drawDetailsInfo(thread);
        ImGui.NextColumn();

        drawDetailsData(thread);
        ImGui.NextColumn();

        ImGui.Columns(1);
      }
    }
  }

  void drawDetailsInfo(ref const ThreadData data) {
    ImGui.Text(data.name);
  }
  void drawDetailsData(ref const ThreadData data) {
    // TODO: real data

    // - Each data entry is a new profile rect.
    // - Not all rects are shown:
    //   - Hidden if too small.
    //   - Merged if too many.
    //   - Shown otherwise
    // - Rects have a label and color only
    // - Must align with rulers!
    // - Traverse depth first:
    //   - Forward scan of the data
    //   - Skipping nodes is adding child count to index
    //   - Matches collection order, all data goes on the stack

    // COLOR
    // - Inherited by default
    // - Alternate coloring by module name
    // - Push/Pop color matches depth first traversal!

    // POSITION & SIZE
    // - X1 is avail-width * start-time / frame-time
    // - X2 is avail-width * end-time   / frame-time
    // - Y1 increments by line-height-with-padding with depth
    // - Y2 is Y1 + line-height-with-padding

    // SCROLLING
    // - This is rendered within a child window
    // - Only draw if visible. Should handle in caller?

    // HOVER
    // - Detailed information tooltip on hover
    // - Highlight all nodes of the same marker

    Draw state = {
    marker:     data.markers.ptr,
    end:        data.markers.ptr + data.markers.length,
    frameTime:  data.markers[0].stop,
    origin:     ImGui.GetCursorScreenPos(),
    list:       ImGui.GetWindowDrawList(),
    lineHeight: ImGui.GetTextLineHeightWithSpacing(),
    availWidth: ImGui.GetWindowWidth() - ImGui.GetCursorPosX()
    };

    auto depth = state.run();
    auto size  = ImVec2(state.availWidth, depth + depth * state.lineHeight);
    ImGui.Dummy(size); // Add layout space to cover our drawings.
  }
}

// Draw markers for a single thread
struct Draw {
  ImDrawList* list;

  const(Marker)* marker;
  const(Marker)* end;
  uint frameTime;

  ImVec2 origin;

  float lineHeight;
  float availWidth;

  int run(int depth = 0) nothrow @nogc {
    assert(marker < end);

    // Draw
    auto pt1 = ImVec2(availWidth * marker.start / frameTime,
                      depth * lineHeight + depth) + origin;
    auto pt2 = ImVec2(availWidth * marker.stop / frameTime - 1,
                      pt1.y + lineHeight);

    pt2.x += origin.x;

    list.AddRectFilled(pt1, pt2, cast(ImU32) ImColor(30, 185, 140, 255));

    char[255] buf = void;
    snprintf(buf.ptr, buf.length, "%.3f ms %s",
             cast(float)marker.stop - marker.start, marker.label);

    pt1.x += 2;
    pt1.y += 2;
    list.AddText(pt1, 0xff000000, buf.ptr);

    // Children
    auto next = depth + 1;
    auto size = next;
    foreach (n; 0..marker.children) {
      marker++;
      size = run(next).max(size);
    }

    return size;
  }
}

struct ThreadData {
  cstring name;
  bool show;
  Marker[] markers;
}

struct Marker {
  cstring label;
  uint start;
  uint stop;
  uint children;
}

immutable threads =
  [ThreadData("Main", true,
              [Marker("__frame", 0, 40, 3),

               Marker("Input", 0, 2, 3),
               Marker("Keyboard", 0, 1, 0),
               Marker("Mouse", 1, 2, 0),
               Marker("Joystick", 2, 3, 0),

               Marker("Update", 3, 20, 2),
               Marker("Audio", 3, 7, 0),
               Marker("Video", 8, 14, 2),
               Marker("GUI", 9, 10, 0),
               Marker("Game", 12, 14, 0),

               Marker("End", 21, 40, 2),
               Marker("Draw", 22, 29, 0),
               Marker("Sync", 30, 40, 0)]),
   ThreadData("GPU", true,
              [Marker("__frame", 0, 40, 0)])];
