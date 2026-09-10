#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE primary_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"June6699.SimpleLive.PrimaryInstance");
  const bool secondary_instance = primary_instance_mutex != nullptr &&
                                  ::GetLastError() == ERROR_ALREADY_EXISTS;
  bool com_initialized = false;

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  const HRESULT co_initialize_result =
      ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  com_initialized = SUCCEEDED(co_initialize_result) ||
                    co_initialize_result == RPC_E_CHANGED_MODE;

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  if (secondary_instance) {
    command_line_arguments.push_back("--simple-live-secondary-instance");
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"simple_live_app", origin, size)) {
    if (com_initialized) {
      ::CoUninitialize();
    }
    if (primary_instance_mutex != nullptr) {
      if (!secondary_instance) {
        ::ReleaseMutex(primary_instance_mutex);
      }
      ::CloseHandle(primary_instance_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (com_initialized) {
    ::CoUninitialize();
  }
  if (primary_instance_mutex != nullptr) {
    if (!secondary_instance) {
      ::ReleaseMutex(primary_instance_mutex);
    }
    ::CloseHandle(primary_instance_mutex);
  }

  // Workaround: flutter_inappwebview_windows 0.6.0 destroys its static
  // WinRT Compositor during DLL_PROCESS_DETACH, after dcomp/CoreMessaging
  // has already shut down. This raises an access violation and surfaces as
  // an "Unknown Hard Error" popup. See:
  //   pichillilorenzo/flutter_inappwebview#2733, #2512
  //   (unfixed on the stable 6.1.5 / windows 0.6.0 release)
  // At this point the window and the Flutter engine are already destroyed
  // and Dart-side _closeAppGracefully has flushed all data, so terminate
  // immediately to skip the faulty static destructors. The OS reclaims any
  // remaining handles. TerminateProcess does not return.
  ::TerminateProcess(::GetCurrentProcess(), 0);
  return EXIT_SUCCESS;
}
