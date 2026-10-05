#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

#include <string>

namespace {
// Hands the command line to an already-running window (single instance, so
// "Open with" on a second PDF opens a tab instead of a second app).
bool ForwardToRunningInstance(const std::vector<std::string>& args) {
  if (args.empty()) return false;
  HWND existing =
      ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
  if (existing == nullptr) return false;
  std::string joined;
  for (const auto& a : args) {
    joined += a;
    joined += '\n';
  }
  COPYDATASTRUCT cds;
  cds.dwData = 0x44535031;  // 'DSP1'
  cds.cbData = static_cast<DWORD>(joined.size());
  cds.lpData = const_cast<char*>(joined.data());
  DWORD_PTR result = 0;
  if (!::SendMessageTimeout(existing, WM_COPYDATA, 0,
                            reinterpret_cast<LPARAM>(&cds), SMTO_ABORTIFHUNG,
                            3000, &result)) {
    return false;
  }
  if (::IsIconic(existing)) ::ShowWindow(existing, SW_RESTORE);
  ::SetForegroundWindow(existing);
  return true;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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

  if (ForwardToRunningInstance(command_line_arguments)) {
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Document Studio", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
