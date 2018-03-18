/**
 * Handling of user input events.
 */
module emulator.input;

import derelict.glfw3.glfw3;

import console = emulator.console;
import gui     = emulator.gui;
import video   = emulator.video;

// State
// -----------------------------------------------------------------------------

private __gshared {
  ubyte connectedJoysticks;
}

// Emulator interface
// -----------------------------------------------------------------------------

// TODO:

// Lifecycle
// -----------------------------------------------------------------------------

package:

void initialize() {
  console.trace("Initialize");

  video.window.glfwSetKeyCallback(&onKey);
  video.window.glfwSetCharCallback(&onChar);
  video.window.glfwSetCursorPosCallback(&onCursorPos);
  video.window.glfwSetCursorEnterCallback(&onCursorEnter);
  video.window.glfwSetMouseButtonCallback(&onMouseButton);
  video.window.glfwSetScrollCallback(&onScroll);

  glfwSetJoystickCallback(&onJoystick);

  foreach (n; 0..GLFW_JOYSTICK_LAST + 1) {
    if (glfwJoystickPresent(GLFW_JOYSTICK_1 + n)) {
      onJoystick(n, GLFW_CONNECTED);
    }
  }
}

void terminate() {
  console.trace("Terminate");

  if (DerelictGLFW3.isLoaded) {
    glfwSetJoystickCallback(null);
  }
}

// Input event callbacks
// -----------------------------------------------------------------------------

// These functions are called from GLFW in response to user input events.

extern(C) private nothrow:

void onKey(GLFWwindow* window, int key, int scancode, int action, int mods) {
  gui.onKey(key, action);
}

void onChar(GLFWwindow* window, uint codepoint) {
  gui.onChar(codepoint);
}

void onCharMods(GLFWwindow* window, uint codepoint, int mods) {

}

void onCursorPos(GLFWwindow* window, double x, double y) {

}

void onCursorEnter(GLFWwindow* window, int entered) {

}

void onMouseButton(GLFWwindow* window, int button, int action, int mods) {
  gui.onMouseButton(button, action);
}

void onScroll(GLFWwindow* window, double xoffset, double yoffset) {
  gui.onScroll(yoffset);
}

void onJoystick(int joy, int event) {
  auto connected = event == GLFW_CONNECTED;
  if (joy < 8) {
    console.info("Joystick #", joy, " ",
                 connected ? "connected" : "disconnected",
                 " (", glfwGetJoystickName(GLFW_JOYSTICK_1 + joy), ")");

    if (connected) {
      connectedJoysticks |= 1 << joy;
    }
    else {
      connectedJoysticks &= ~(1 << joy);
    }
  }
  else if (connected) {
    console.warn("Ignoring joystick #", joy, " (ID greater than 7)");
  }
}
