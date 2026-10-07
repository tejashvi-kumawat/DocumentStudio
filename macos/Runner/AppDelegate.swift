import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Files opened from Finder before Flutter is up, delivered once it is.
  private var pendingOpen: [String] = []
  private var openChannel: FlutterMethodChannel?
  private var dartReady = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      openChannel = FlutterMethodChannel(
        name: "document_studio/open", binaryMessenger: controller.engine.binaryMessenger)
      // Dart says "ready" once its handler is installed; until then files wait.
      openChannel?.setMethodCallHandler { [weak self] call, result in
        if call.method == "ready" {
          self?.dartReady = true
          self?.flushPending()
        }
        result(nil)
      }
    }
    super.applicationDidFinishLaunching(notification)
  }

  /// Double-click / "Open With" on a PDF: macOS runs one instance and calls
  /// this, so the file opens as a tab in the running window.
  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    pendingOpen.append(contentsOf: filenames)
    flushPending()
    NSApp.activate(ignoringOtherApps: true)
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    sender.reply(toOpenOrPrint: .success)
  }

  private func flushPending() {
    guard dartReady, let channel = openChannel, !pendingOpen.isEmpty else { return }
    let files = pendingOpen
    pendingOpen = []
    channel.invokeMethod("open", arguments: files)
  }
}
