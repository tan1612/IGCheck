#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

#include <cstdio>
#include <fstream>

static LONG WINAPI CrashHandler(EXCEPTION_POINTERS* exceptionInfo) {
  std::ofstream log("app_crash.log", std::ios::app);
  if (log.is_open()) {
    log << "Crash exception code: 0x" << std::hex
        << exceptionInfo->ExceptionRecord->ExceptionCode
        << " at address: 0x" << exceptionInfo->ExceptionRecord->ExceptionAddress
        << std::endl;
  }
  return EXCEPTION_CONTINUE_SEARCH;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Always set working directory to the directory containing igcheck.exe
  wchar_t exePath[MAX_PATH];
  GetModuleFileNameW(nullptr, exePath, MAX_PATH);
  std::wstring::size_type pos = std::wstring(exePath).find_last_of(L"\\/");
  if (pos != std::wstring::npos) {
    SetCurrentDirectoryW(std::wstring(exePath).substr(0, pos).c_str());
  }

  ::SetUnhandledExceptionFilter(CrashHandler);
  FILE* fpStdout = nullptr;
  FILE* fpStderr = nullptr;
  freopen_s(&fpStdout, "app_stdout.log", "w", stdout);
  freopen_s(&fpStderr, "app_stderr.log", "w", stderr);

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"IGCheck - PairIG Review", origin, size)) {
    return EXIT_FAILURE;
  }
  window.Show();
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
