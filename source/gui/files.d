/**
 * Displays a files navigation tree.
 */
module gui.files;

import core.sync.mutex : Mutex;
import core.sync.condition : Condition;

import std.algorithm : filter, map;
import std.array  : array, empty;
import std.conv   : to;
import std.file   : DirEntry, SpanMode, dirEntries;
import std.path   : baseName, extension;
import std.string : toStringz;

import derelict.opengl;

import imgui;

import emulator.util : cstring, glCheck;
import system = emulator.system;
import video  = emulator.video;
import worker = emulator.worker;

import gui.icons;
import layout = gui.layout : Window;

private __gshared {
  string filesPath = "files";
  FileInfo[] files;

  TextureAtlas icons;
  int dirIconIndex;

  TaskState taskState;
}

private enum TaskState : ubyte {
  done,   /// Task is not running.
  scan,   /// Task is scanning for supported files.
  upload, /// Task is requesting a batch of GPU uploads.
  finish  /// Task has requested the last batch of GPU uploads.
}

private struct FileInfo {
  string  path;
  cstring name;
  cstring lastPlayed;
  int     iconIndex;
  bool    isDir;
  bool    hasSaveFile;
}

void refresh() {
  assert(taskState == TaskState.done);

  files = null;
  icons.clear();

  taskState = TaskState.scan;

  worker.submit(&refreshTask);
}

private void refreshTask() {
  // Scan for supported files at the current path.
  files = filesPath
    .dirEntries(SpanMode.shallow)
    .filter!supportedFile()
    .map!getFileInfo()
    .array();

  // TODO: read file data

}

bool supportedFile(DirEntry e) {
  if (e.isDir) {
    return true;
  }

  auto ext = e.name.extension;
  return !ext.empty && system.isExtensionSupported(ext);
}

FileInfo getFileInfo(DirEntry e) {
  FileInfo file = {
  path:      e.name,
  name:      e.name.baseName(e.name.extension).toStringz(),
  isDir:     e.isDir,
  iconIndex: e.isDir ? dirIconIndex : -1,
  };
  return file;
}

private int getIconIndex(ref DirEntry e) {
  return -1;
}

private void uploadSprites() {


  if (taskState == TaskState.finish) {
    taskState = TaskState.done;
  }
}

/// GUI window displaying ROM files in the user's data directory.
class FilesWindow : Window {
  this() {
    assert(icons is null);

    super("Files".ptr,
          ImGuiWindowFlags_NoScrollbar |
          ImGuiWindowFlags_NoScrollWithMouse);

    icons = new TextureAtlas(4096, 4096, 64, 64);
    refresh();
  }

  ~this() {
    delete icons;
  }

  protected override void draw() {
    if (taskState >= TaskState.upload) {
      uploadSprites();
    }

    auto disabled = taskState != TaskState.done;
    if (disabled) layout.ImGui_BeginDisabled();

    enum refreshLabel = ICON_FA_REFRESH ~ " Refresh";
    if (ImGui.Button(refreshLabel)) {
      refresh();
    }

    if (disabled) layout.ImGui_EndDisabled();

    auto fs = files;
    auto hoverColor = ImVec4(.2, .3, .4, .8);
    auto textAlign = ImVec2(0, .5);
    auto area = ImGui.GetContentRegionAvail();
    auto size = area;
    size.y = 20;

    ImGui.Separator();
    ImGui.BeginChild("scrolling", area);
    // ImGui.PushStyleVar(ImGuiStyleVar_ItemSpacing,     ImVec2_zero);
    // ImGui.PushStyleVar(ImGuiStyleVar_ButtonTextAlign, textAlign);
    // ImGui.PushStyleColor(ImGuiCol_Button,        ImVec4_zero);
    // ImGui.PushStyleColor(ImGuiCol_ButtonHovered, hoverColor);

    auto clipper  = ImGuiListClipper(cast(uint) fs.length, size.y);
    auto flags    = ImGuiSelectableFlags_SpanAllColumns;
    auto iconSize = ImVec2(16, 16);

    while (clipper.Step()) {
      foreach (ref file; fs[clipper.DisplayStart..clipper.DisplayEnd]) {
        bool open;

        enum {
          iconWidth = 20,
          extraWidth = 100
        }

        auto available = ImGui.GetWindowWidth() - iconWidth - extraWidth * 2;

        ImGui.Columns(4);
        ImGui.SetColumnWidth(0, iconWidth);
        ImGui.SetColumnWidth(1, available);
        ImGui.SetColumnWidth(2, extraWidth);
        ImGui.SetColumnWidth(3, extraWidth);

        if (file.iconIndex != -1) {
          ImGui.Text("%d", file.iconIndex);
          // auto sprite = &icons.sprites[file.iconIndex];
          // ImGui.Image(cast(ImTextureID) sprite.texture, iconSize,
          //             sprite.uv0, sprite.uv1);
        }
        ImGui.NextColumn();

        open |= ImGui.Selectable(file.name, false, flags);
        ImGui.NextColumn();

        open |= ImGui.Selectable("Hello", false, flags);
        ImGui.NextColumn();

        open |= ImGui.Selectable("World", false, flags);
        ImGui.NextColumn();

        ImGui.Columns(1);

        if (open) {
          system.loader.open(file.path.to!string);
        }
      }
    }

    clipper.End();

    // ImGui.PopStyleColor(2);
    // ImGui.PopStyleVar(2);
    ImGui.EndChild();
  }
}

// Texture Atlas
// -----------------------------------------------------------------------------

import std.bitmanip : BitArray;

/**
 * A very simple texture atlas storing only rectangle sprites.
 */
class TextureAtlas {
  static struct Sprite {
    // Hot
    ImVec2 uv0;
    ImVec2 uv1;
    GLuint texture;
    // Cold
    ushort x;
    ushort y;
  }

  private {
    // Hot
    Sprite[] sprites;
    GLuint[] textures;
    BitArray usage;
    // Cold
    ushort texWidth;
    ushort texHeight;
    ushort width;
    ushort height;
    uint countPerTexture;
    uint totalAllocated;
    uint internalFormat;
  }

  this(ushort texWidth, ushort texHeight, ushort width, ushort height,
       GLuint internalFormat = GL_RGBA8)
  {
    this.texWidth  = texWidth;
    this.texHeight = texHeight;
    this.width  = width;
    this.height = height;

    this.internalFormat = internalFormat;

    countPerTexture = (texWidth / width) * (texHeight / height);
  }

  ~this() {
    clear();
  }

  int alloc(in void* pixels, GLuint format = GL_BGRA) {
    auto idx = -1;

    if ((totalAllocated % countPerTexture) == 0) {
      auto n = sprites.length;

      sprites.length += countPerTexture;
      usage  .length  = sprites.length;

      foreach (ushort y; 0..height) {
        foreach (ushort x; 0..width) {
          auto sprite = &sprites[n++];
          sprite.x = x;
          sprite.y = y;

          auto xf = cast(float) x;
          auto yf = cast(float) y;
          sprite.uv0 = ImVec2( xf          / texWidth,  yf           / texWidth);
          sprite.uv1 = ImVec2((xf + width) / texWidth, (yf + height) / texHeight);
        }
      }

      textures.length += 1;

      glGenTextures(1, &textures[$-1]);
      video.gl.texture2D = textures[$-1];
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      glTexImage2D(GL_TEXTURE_2D, 0, internalFormat, texWidth, texHeight,
                   0, GL_BGRA, GL_UNSIGNED_BYTE, null);

      idx = totalAllocated;
    }
    else {
      foreach (n; 0 .. cast(int) usage.length) {
        if (!usage[n]) {
          idx = n;
          break;
        }
      }
    }

    assert(idx != -1);
    usage[idx] = true;

    auto sprite = &sprites[idx];
    sprite.texture = textures[idx / countPerTexture];

    video.gl.texture2D = sprite.texture;
    glTexSubImage2D(GL_TEXTURE_2D, 0, sprite.x, sprite.y, width, height,
                    format, GL_UNSIGNED_BYTE, pixels);
    glCheck();

    totalAllocated++;
    return idx;
  }

  void free(int id) {
    assert(id >= 0 && id < usage.length);
    if (usage[id]) {
      usage[id] = false;
    }
  }

  void clear() {
    if (textures.length) {
      glDeleteTextures(cast(GLuint) textures.length, textures.ptr);

      textures.length = 0;
      usage   .length = 0;
      sprites .length = 0;

      totalAllocated = 0;
    }
  }
}
