/**
 * Background worker thread.
 */
module emulator.worker;

import core.sync.condition : Condition;
import core.sync.mutex     : Mutex;
import core.thread : Thread;

alias TaskFn0 = void function();
alias TaskFn1 = void function(void* arg); /// Signature of a task function.

private struct Task {
  TaskFn1 fn;
  void*   arg;
}

private __gshared {
  Mutex     _mutex;      /// Critical section used to synchronize queue access.
  Condition _condition;  /// Condition variable used to notify of new tasks.
  Thread[]  _threads;    /// Worker threads running tasks.
  Task[]    _queue;      /// Ring buffer of queued tasks.
  ushort    _queueStart; /// Index of the first allocated task in the queue.
  ushort    _queueCount; /// Number of allocated tasks in the queue.
  ubyte     _tasksCount; /// Number of tasks currently running concurrently.
}

package void initialize() {
  _queue = new Task[512];

  _mutex     = new Mutex();
  _condition = new Condition(_mutex);
  _threads   = new Thread[2];

  _tasksCount = cast(ubyte) _threads.length;

  foreach (ref t; _threads) {
    t = new Thread(&run);
    t.start();
  }
}

package void terminate() {
  synchronized (_mutex) {
    _queueCount = 0;
  }

  _condition.notifyAll();

  foreach (t; _threads) {
    t.join();
  }

  _threads   = null;
  _condition = null;
  _mutex     = null;
  _queue     = null;
}

private void simpleTask(void* fn) {
  (cast(TaskFn0) fn)();
}

/// Submits an asynchronous task, waking up a worker if needed.
void submit(TaskFn0 task) {
  submit(&simpleTask, task);
}
/// ditto
void submit(TaskFn1 task, void* arg) {
  synchronized (_mutex) {
    auto index = (_queueStart + _queueCount++) % _queue.length;
    assert(_queueCount < _queue.length, "Worker queue full");

    _queue[index] = Task(task, arg);

    if (_tasksCount < _threads.length) {
      _tasksCount++;
      _condition.notify();
    }
  }
}

private void run() {
  auto index = size_t.max;

  while (true) {
    Task task;

    synchronized (_mutex) {
      // Remove the last task from the queue.
      if (index != size_t.max) {
        _queue[index].fn = null;

        if (index == _queueStart) {
          auto end = queueEnd();
          do {
            _queueStart = cast(ushort) queueNext(_queueStart);
            _queueCount--;
          }
          while (_queueStart != end && _queue[_queueStart].fn is null);
        }
      }

      // Wait for a new task.
      if (_queueCount == 0) {
        _tasksCount--;
        _condition.wait();
      }

      // Find a task to run.
      auto end = queueEnd();
      index = _queueStart;

      while (index != end) {
        task = _queue[index];

        if (task.fn !is null) {
          break;
        }

        index = queueNext(index);
      }
    }

    // Program is exiting when workers are notified without any tasks.
    if (task.fn is null) {
      return;
    }

    // Run the task and move to the next one.
    task.fn(task.arg);
  }
}

size_t queueEnd() nothrow @nogc {
  return (_queueStart + _queueCount) % _queue.length;
}

size_t queueNext(size_t index) nothrow @nogc {
  return (index + 1) % _queue.length;
}
