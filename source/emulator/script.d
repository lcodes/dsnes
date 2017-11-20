/**
 * Lua scripting integration.
 */
module emulator.script;

import std.array     : empty;
import std.conv      : to;
import std.exception : assumeUnique, enforce;
import std.file      : exists;
import std.string    : toStringz;

import derelict.lua.lua;

import emulator.util : cstring, dispose;

import console = emulator.console;
import system  = emulator.system;

// Core
// -------------------------------------------------------------------------------------------------

private __gshared {
  lua_State* L;
  string initFilePath = "init.lua";
}

enum tracebackIdx = 1;

nothrow @nogc {
  string initFile() { return initFilePath; }
  void initFile(string path) {
    assert(L is null);
    initFilePath = path;
  }

  cstring getCString(int index) {
    try {
      return cast(cstring) L.lua_tostring(index);
    }
    catch (Exception e) {
      assert(0, e.msg); // FIXME
    }
  }

  string getString(int index) {
    size_t len;
    return L.lua_tolstring(index, &len)[0..len].assumeUnique;
  }
}

int luaCheck(int result, int errorIdx = -1) {
  if (result != 0) throw new Exception(errorIdx.getString());
  return result;
}

package:

void initialize() {
  console.trace("Initialize");
  assert(!DerelictLua.isLoaded);

  // Shared library.
  DerelictLua.load();
  auto ptr = null.lua_version(); assert(ptr);
  auto ver = to!int(*ptr);
  auto major = ver / 100;
  auto minor = ver % 100;
  console.verbose("Lua version ", major, '.', minor);

  // State.
  L = luaL_newstate();
  enforce(L !is null, "Failed to init Lua.");

  // Error handling.
  L.lua_atpanic(&panic);
  L.lua_pushcfunction(&traceback);
  assert(L.lua_gettop == tracebackIdx);

  // Standard libraries.
  openlib("_G",            luaopen_base);
  openlib(LUA_LOADLIBNAME, luaopen_package);
  openlib(LUA_COLIBNAME,   luaopen_coroutine);
  openlib(LUA_TABLIBNAME,  luaopen_table);
  openlib(LUA_IOLIBNAME,   luaopen_io);
  openlib(LUA_OSLIBNAME,   luaopen_os);
  openlib(LUA_STRLIBNAME,  luaopen_string);
  openlib(LUA_MATHLIBNAME, luaopen_math);
  openlib(LUA_UTF8LIBNAME, luaopen_utf8);
  openlib(LUA_DBLIBNAME,   luaopen_debug);

  // Native libraries.
  // push("");

  // Initialization scripts.
  load("script/core.lua");
  if (!initFilePath.empty) initFilePath.load();

  assert(L.lua_gettop == tracebackIdx);
}

void terminate() {
  console.trace("Terminate");
  if (!DerelictLua.isLoaded) return;

  L.dispose!lua_close();
  DerelictLua.unload();
}

void load(string fileName) {
  if (!fileName.exists) {
    console.warn("File ", fileName, " does not exists.");
  }
  else {
    console.verbose("Loading ", fileName);
    L.luaL_loadfile(fileName.toStringz).luaCheck;
    L.lua_pcall(0, 0, tracebackIdx).luaCheck;
  }
}

void run() {
  // TODO: tick frame
}

void push(string s) { L.lua_pushlstring(s.ptr, s.length); }

private:

void openlib(cstring name, lua_CFunction open) {
  console.trace("Open library ", name);
  L.luaL_requiref(name, open, 1);
  L.lua_pop(1);
}

// Internals
// -------------------------------------------------------------------------------------------------

private extern (C) nothrow @nogc:

int panic(lua_State* L) {
  assert(0, "Lua panic");
}

int traceback(lua_State* L) {
  try {
    L.lua_getglobal("debug");
    L.lua_getfield(-1, "traceback");
    L.lua_pushvalue(1);
    L.lua_pushinteger(2);
    L.lua_call(2, 1);
    return 1;
  }
  catch (Exception e) {
    assert(0, e.msg); // FIXME
  }
}
