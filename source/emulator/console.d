/**
 * A text-only interface between the user and the emulator. Contains commands,
 * variables and logs.
 */
module emulator.console;

import std.algorithm  : countUntil;
import std.array      : empty;
import std.conv       : to;
import std.datetime   : Clock, SysTime;
import std.exception  : enforce;
import std.file       : exists;
import std.functional : toDelegate;
import std.json       : JSONValue;
import std.stdio      : File;

import system = emulator.system;

private __gshared {
  JSONValue[string] memento; /// Serialized JSON cvars. Used when loading and saving variable state.

  string[string] descs;      /// User-friendly descriptions for console commands and variables.
  JsonVar[TypeInfo] json;    /// JSON reader and writer delegate pairs for variables.

  Cmd[string] cmds;          /// Console commands. Used to expose functions to users.
  Var[string] vars;          /// Console variables. Used to expose settings to users.

  ILogger[] loggers;         /// Registered loggers. They all consume every message as a const ref.

  LogSettings settings;

  struct LogSettings {
    LogLevel level  = LogLevel.all;
    bool showColors = true;
    bool showTime   = true;
    bool showModule = true;
    bool showThread = true;
    bool showLevel  = true;
  }
}

// Console
// -----------------------------------------------------------------------------

package void initialize() {
  add(new StdoutLogger());

  trace("Initialize");
}

package void terminate() {
  trace("Terminate");

  loggers = null;
}

void exec(string line) {
  console.trace("Exec: ", line);

  auto cmdLine = line.parseCmdLine();
  enforce(!cmdLine.empty, "Empty command");

  auto cmd = cmdLine[0] in cmds;
  if (cmd !is null) (*cmd)(cmdLine[1..$]);

  auto var = cmdLine[0] in vars;
  enforce(var !is null, "Not found");

  switch (cmdLine.length) {
  case 2:  enforce(false, "Expecting '= value'"); break;
  default: enforce(false, "Too many arguments"); break;

  case 1: // foo
    assert(0);
    // break;

  case 3: // foo = bar
    assert(0);
    // break;
  }
}

string[] parseCmdLine(string line) {
  return null; // TODO:
}

private string check(string name) {
  assert(name !in cmds);
  assert(name !in vars);
  return name;
}

void desc(string name, string value) { descs[name] = value; }
string desc(string name) {
  auto p = name in descs;
  return p is null ? "" : *p;
}

// Commands
// -------------------------------------------------------------------------------------------------

alias Cmd = void function(string[] args);

void add(Cmd cmd, string name) {
  console.trace("New Command: ", name);
  cmds[name.check] = cmd;
}

void add(Cmd cmd, string name, string altName) {
  add(cmd, name);
  add(cmd, altName);
}

// Variables
// -------------------------------------------------------------------------------------------------

alias Json = JSONValue;

alias ToJson   = Json delegate();
alias FromJson = void delegate(Json);

private struct JsonVar {
  ToJson   toJson;
  FromJson fromJson;
}

private struct Var {
  TypeInfo type;
  Read     read;
  Write    write;
  Change   handler;

  alias Read     = void* delegate();
  alias Write    = void delegate(void*);
  alias Change   = void function();
}

void add(T, alias read, alias write)(string name, Var.Change change = null) {
  Json toJson() { assert(0); }
  void fromJson(Json v) { assert(0); }

  console.trace("New Variable: ", name, " (", T.stringof, ")");
  vars[name.check] = Var(typeid(T), toDelegate(&read), toDelegate(&write), change);
  json[typeid(T)]  = JsonVar(&toJson, &fromJson);

  auto p = name in memento;
  if (p !is null) {
    // TODO:
  }
}

void add(T)(string name, T* data, Var.Change change = null) {
  void* read() { return data; }
  void write(void* value) { *data = *cast(T*) value; }
  Json toJson() { assert(0); }
  void fromJson(Json v) { assert(0); }

  console.trace("New Variable: ", name, " (", T.stringof, ")");
  vars[name.check] = Var(typeid(T), &read, &write, change);
  json[typeid(T)]  = JsonVar(&toJson, &fromJson);

  auto p = name in memento;
  if (p !is null) {
    // auto data = (*p).as!T;
    // write(&data);
  }
}

private Var* var(T)(string name) {
  auto p = name in vars;
  enforce(p);
  assert(p.type is typeid(T));
  return p;
}

T readVar(T)(string name) {
  return *cast(T*) var!T(name).data;
}

void writeVar(T)(string name, T* value) {
  auto v = var!T(name);
  v.write(value);
  if (v.change !is null) v.change();
}

JSONValue serialize() {
  assert(0);
}

void deserialize(JSONValue v) {
  assert(0);
}

// History
// -----------------------------------------------------------------------------

// TODO:

// Logging
// -----------------------------------------------------------------------------

enum LogLevel {
  all,     /// Enable everything
  trace,   /// Execution traces
  verbose, /// Optional messages
  data,    /// Console output
  info,    /// Important messages
  warn,    /// Important alerts
  dbg,     /// Development messages
  error,   /// Execution failures
  fatal,   /// Application crashes
  none     /// Enable nothing
}

/// Logging message. Allocated on the stack during dispatch.
struct LogEntry {
  string   namespace; /// D module where the message was emitted.
  string   message;   /// Text of the message.
  SysTime  time;      /// Current time.
  LogLevel level;     /// Severity of the message. Used for filtering.

  /// Generates a human readable string representation of the message.
  string format(ILogger cfg) const {
    if (level == LogLevel.data) return message;
    return text(/*time, " ",*/
                cfg.color(level), level,
                cfg.black, " [",
                cfg.reset, namespace,
                cfg.black, "] ",
                cfg.reset, message);
  }
}

/// Logging interface, defines a log message sink.
interface ILogger {
  nothrow @nogc {
    /// Only receive log messages whose level is equal or greater than this.
    LogLevel logLevel();
    /// ditto
    void logLevel(LogLevel value);
  }

protected:
  /// Called when a log message is dispatched.
  void logWrite(ref const LogEntry e);

@nogc:
  /// Returns a string to change text color.
  string color(LogLevel level);
  /// ditto
  string black();
  /// ditto
  string reset();
}

/// Base logger implementation.
abstract class Logger : ILogger {
  protected LogLevel _logLevel;

  override LogLevel logLevel() { return _logLevel; }
  override void logLevel(LogLevel value) { _logLevel = value; }

  protected abstract void logWrite(ref const LogEntry e);

protected @nogc:
  string color(LogLevel level) { return ""; }
  string black() { return ""; }
  string reset() { return ""; }
}

/// Registers a new log sink to receive log messages passing its level filter.
void add(ILogger logger) {
  loggers ~= logger;
}

void remove(ILogger logger) {
  auto idx = loggers.countUntil!"a is b"(logger);
  if (idx != -1) {
    loggers[idx] = null;
  }
}

nothrow:

@nogc {
  /// Logging level. All log messages whose level is below this are ignored.
  LogLevel logLevel() { return settings.level; }
  /// ditto
  void setLogLevel(LogLevel value) { settings.level = value; }
}

/// Low-level logging function. Dispatches a LogEntry to all registered sinks.
void log(LogLevel level, string mod, string message)
in {
  assert(level >= logLevel);
  assert(!mod.empty);
}
body {
  try {
    auto entry = LogEntry(mod, message, Clock.currTime, level);

    foreach (logger; loggers) {
      if (logger is null || logger.logLevel > level) continue;

      try logger.logWrite(entry);
      catch (Exception e) logError(e, message);
    }
  }
  catch (Exception e) {
    logError(e, message);
  }
}

/// Prints a fatal logging failure to standard error.
private void logError(Exception e, string msg) {
  import core.stdc.stdio : fprintf, stderr; // Don't care if this one fails.

  stderr.fprintf("FATAL: %*.s\n", cast(uint) e.msg.length, e.msg.ptr);
  stderr.fprintf("ERROR: %*.s\n", cast(uint)   msg.length,   msg.ptr);
}

/// Development logging. Removed in release builds.
debug template dbg(string mod  = __MODULE__,
                   string file = __FILE__,
                   uint   line = __LINE__)
{
  void dbg(Args...)(Args args) {
    if (LogLevel.dbg >= logLevel) {
      log(LogLevel.dbg, mod, text(args, "\n  @ ", file, ':', line));
    }
  }
}
else {
  void dbg(Args...)(Args) {}
}

/// Unformatted logging.
void trace(string mod = __MODULE__, Args...)(Args args) {
  if (LogLevel.trace >= logLevel) log(LogLevel.trace, mod, args.text);
}
/// ditto
void verbose(string mod = __MODULE__, Args...)(Args args) {
  if (LogLevel.verbose >= logLevel) log(LogLevel.verbose, mod, args.text);
}
/// ditto
void info(string mod = __MODULE__, Args...)(Args args) {
  if (LogLevel.info >= logLevel) log(LogLevel.info, mod, args.text);
}
/// ditto
void warn(string mod = __MODULE__, Args...)(Args args) {
  if (LogLevel.warn >= logLevel) log(LogLevel.warn, mod, args.text);
}
/// ditto
void error(string mod = __MODULE__, Args...)(Args args) {
  if (LogLevel.error >= logLevel) log(LogLevel.error, mod, args.text);
}
/// ditto
void fatal(string mod = __MODULE__, Args...)(Args args) {
  if (LogLevel.fatal >= logLevel) log(LogLevel.fatal, mod, args.text);
}

/// Formatted logging.
void tracef(string mod = __MODULE__, Args...)(string fmt, Args args) {
  if (LogLevel.trace >= logLevel) logf(LogLevel.trace, mod, fmt, args);
}
/// ditto
void verbosef(string mod = __MODULE__, Args...)(string fmt, Args args) {
  if (LogLevel.verbose >= logLevel) logf(LogLevel.verbose, mod, fmt, args);
}
/// ditto
void infof(string mod = __MODULE__, Args...)(string fmt, Args args) {
  if (LogLevel.info >= logLevel) logf(LogLevel.info, mod, fmt, args);
}
/// ditto
void warnf(string mod = __MODULE__, Args...)(string fmt, Args args) {
  if (LogLevel.warn >= logLevel) logf(LogLevel.warn, mod, fmt, args);
}
/// ditto
void errorf(string mod = __MODULE__, Args...)(string fmt, Args args) {
  if (LogLevel.error >= logLevel) logf(LogLevel.error, mod, fmt, args);
}
/// ditto
void fatalf(string mod = __MODULE__, Args...)(string fmt, Args args) {
  if (LogLevel.fatal >= logLevel) logf(LogLevel.fatal, mod, fmt, args);
}

/// Same as std.conv.text but returns the error message on failure.
private string text(Args...)(Args args) {
  static import std.conv;

  try return std.conv.text(args);
  catch (Exception e) return e.msg;
}

/// Simulate `import console = emulator.console;`
private struct console {
  @disable this();

  alias trace   = .trace;
  alias verbose = .verbose;
  alias info    = .info;
  alias warn    = .warn;
  alias dbg     = .dbg;
  alias error   = .error;
  alias fatal   = .fatal;
}

// STDOUT Logger
// -----------------------------------------------------------------------------

/// Generates an ANSI color code at compile time. Used by StdoutLogger.color.
private template ansiColor(string code) {
  enum ansiColor = "\x1B[" ~ code ~ "m";
}

/// Log sink writing to standard output with ANSI color codes.
class StdoutLogger : Logger {
protected override:

  void logWrite(ref const LogEntry entry) {
    import std.stdio : stderr, stdout;

    auto output = entry.level > LogLevel.warn ? stderr : stdout;
    output.writeln(entry.format(this));
  }

@nogc:

  string color(LogLevel level) {
    final switch (level) with (LogLevel) {
    case all:
    case none:    assert(0);
    case fatal:   return ansiColor!"41;37";
    case error:   return ansiColor!"1;31";
    case dbg:     return ansiColor!"1;36";
    case warn:    return ansiColor!"1;33";
    case info:    return ansiColor!"1;32";
    case data:    return ansiColor!"37";
    case verbose: return ansiColor!"32";
    case trace:   return ansiColor!"1;30";
    }
  }

  string black() { return ansiColor!"1;49;30"; }
  string reset() { return ansiColor!"0"; }
}
