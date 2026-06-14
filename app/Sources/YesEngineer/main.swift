import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let menubar = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menubar.start()
        DispatchQueue.main.async { [weak self] in
            self?.menubar.showControlPanel()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
