/**
 * Host platform statistics for the running process.
 *
 * The following statistics are supported:
 * - CPU usage.
 * - Memory usage.
 * - Battery level. TODO
 *
 * References:
 *   https://chromium.googlesource.com/chromium/src/+/master/base/process/process_metrics_mac.cc
 */
module emulator.platform;

// Linux
// -----------------------------------------------------------------------------

version (linux) {
  static assert(0, "TODO");

  package void initialize() {

  }

  package void terminate() {

  }
}

// macOS
// -----------------------------------------------------------------------------

else version (OSX) {
  import core.time : MonoTime, TickDuration;

  import core.sys.darwin.mach.kern_return;
  import core.sys.darwin.mach.thread_act;
  import core.sys.posix.sys.time;

private nothrow @nogc:

  struct task;

  alias mach_vm_size_t = ulong;
  alias policy_t       = int;
  alias task_name_t    = task*;
  alias task_flavor_t  = natural_t;
  alias task_info_t    = int*;

  struct time_value_t {
    int seconds;
    int microseconds;
  }

  struct task_thread_times_info {
    time_value_t user_time;
    time_value_t system_time;
  }

  struct task_basic_info_64 {
    align(1):
    int            suspend_count;
    mach_vm_size_t virtual_size;
    mach_vm_size_t resident_size;
    time_value_t   user_time;
    time_value_t   system_time;
    policy_t       policy;
  }

  struct task_vm_info {
    mach_vm_size_t virtual_size;
    int            region_count;
    int            page_size;
    mach_vm_size_t resident_size;
    mach_vm_size_t resident_size_peak;
    mach_vm_size_t device;
    mach_vm_size_t device_peak;
    mach_vm_size_t internal;
    mach_vm_size_t internal_peak;
    mach_vm_size_t external;
    mach_vm_size_t external_peak;
    mach_vm_size_t reusable;
    mach_vm_size_t reusable_peak;
    mach_vm_size_t purgeable_volatile_pmap;
    mach_vm_size_t purgeable_volatile_resident;
    mach_vm_size_t purgeable_volatile_virtual;
    mach_vm_size_t compressed;
    mach_vm_size_t compressed_peak;
    mach_vm_size_t compressed_lifetime;
    mach_vm_size_t phys_footprint;
    // mach_vm_address_t min_address;
    // mach_vm_address_t max_address;
  }

  alias task_thread_times_info task_thread_times_info_data_t;
  alias task_basic_info_64     task_basic_info_64_data_t;
  alias task_vm_info           task_vm_info_data_t;

  enum uint TASK_THREAD_TIMES_INFO = 3;
  enum uint TASK_THREAD_TIMES_INFO_COUNT =
    task_thread_times_info_data_t.sizeof / int.sizeof;

  enum uint TASK_BASIC_INFO_64 = 5;
  enum uint TASK_BASIC_INFO_64_COUNT =
    task_basic_info_64_data_t.sizeof / int.sizeof;

  enum uint TASK_VM_INFO = 22;
  enum uint TASK_VM_INFO_COUNT =
    task_vm_info_data_t.sizeof / int.sizeof;

  extern (C) {
    task_name_t mach_task_self();

    kern_return_t task_info(task_name_t target_task,
                            task_flavor_t flavor,
                            task_info_t task_info_out,
                            mach_msg_type_number_t* task_info_outCnt);
  }

  __gshared {
    task_name_t self;
    MonoTime lastCpuTime;
    ulong lastSystemTime;
  }

  package void initialize() {
    self = mach_task_self();
  }

  package void terminate() {
    self = null;
  }

  void timeradd(ref const timeval a, ref const timeval b, ref timeval result) {
    result.tv_sec  = a.tv_sec  + b.tv_sec;
    result.tv_usec = a.tv_usec + b.tv_usec;
    if (result.tv_usec >= 1000000) {
      result.tv_sec++;
      result.tv_usec -= 1000000;
    }
  }

  void to(ref const time_value_t src, ref timeval dst) {
    dst.tv_sec  = src.seconds;
    dst.tv_usec = src.microseconds;
  }

  long usecs(ref const timeval tv) {
    return tv.tv_sec * 1000000 + tv.tv_usec;
  }

  public double cpuUsage() {
    task_thread_times_info threadTimesInfo = void;

    auto count = TASK_THREAD_TIMES_INFO_COUNT;
    auto kr = self.task_info(TASK_THREAD_TIMES_INFO,
                             cast(task_info_t) &threadTimesInfo, &count);
    if (kr != KERN_SUCCESS) return 0;

    task_basic_info_64 basicInfo = void;
    count = TASK_BASIC_INFO_64_COUNT;
    kr = self.task_info(TASK_BASIC_INFO_64,
                        cast(task_info_t) &basicInfo, &count);
    if (kr != KERN_SUCCESS) return 0;

    timeval user = void, system = void, task = void;
    threadTimesInfo.user_time  .to(user);
    threadTimesInfo.system_time.to(system);
    timeradd(user, system, task);

    basicInfo.user_time  .to(user);
    basicInfo.system_time.to(system);
    timeradd(user,   task, task);
    timeradd(system, task, task);

    auto time = MonoTime.currTime;
    auto selfTime = task.usecs;

    if (lastSystemTime == 0) {
      lastCpuTime = time;
      lastSystemTime = selfTime;
      return 0;
    }

    auto systemTimeDelta = selfTime - lastSystemTime;
    auto timeDelta = (cast(TickDuration) (time - lastCpuTime)).usecs;
    if (timeDelta == 0) {
      return 0;
    }

    lastCpuTime = time;
    lastSystemTime = selfTime;

    return cast(double) (systemTimeDelta * 100) / timeDelta;
  }

  public double memoryUsage() {
    task_vm_info info = void;
    auto count = TASK_VM_INFO_COUNT;
    auto kr = self.task_info(TASK_VM_INFO, cast(task_info_t) &info, &count);
    if (kr != KERN_SUCCESS) return 0;
    return cast(double) info.resident_size / 1024 / 1024;
  }
}

// Windows
// -----------------------------------------------------------------------------

else version (Windows) {
  static assert(0, "TODO");

  package void initialize() {

  }

  package void terminate() {

  }
}

else static assert(0);
