#include <webview_cef/webview_cef_plugin.h>

#include "my_application.h"

int main(int argc, char** argv) {
  // CEF starts its helper processes (renderer, GPU, utility) from this same
  // executable. Each of them must run CEF's own entry point and return here,
  // before GTK or Flutter start; otherwise every helper boots a full copy of
  // App Studio. The plugin's own script that was meant to add this patches
  // linux/main.cc, which current Flutter no longer generates.
  int exit_code = initCEFProcesses(argc, argv);
  if (exit_code >= 0) {
    return exit_code;
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
