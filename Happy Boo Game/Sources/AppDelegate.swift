import Cocoa
import SpriteKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var skView: SKView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsStore.shared.load()

        skView = SKView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 60

        window = NSWindow(
            contentRect: skView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Happy Boo Game"
        window.contentView = skView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        SceneRouter.shared.configure(view: skView)
        if SettingsStore.shared.profile.username.isEmpty {
            SceneRouter.shared.showUsername()
        } else {
            SceneRouter.shared.showTitle()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
