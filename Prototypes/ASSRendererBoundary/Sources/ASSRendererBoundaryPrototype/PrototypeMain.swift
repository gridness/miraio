import AppKit
import Foundation

@MainActor
final class PrototypeAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var controller: PrototypeViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let videoURL = try FixtureVideo.makeIfNeeded()
            guard let subtitleURL = Bundle.module.url(
                forResource: "fidelity-matrix",
                withExtension: "ass",
                subdirectory: "Fixtures"
            ) else {
                throw PrototypeError.fixture("Bundled ASS fixture is missing")
            }
            let subtitleData = try Data(contentsOf: subtitleURL)
            let controller = try PrototypeViewController(
                videoURL: videoURL,
                subtitleData: subtitleData
            )

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.tabbingMode = .disallowed
            window.title = "Miraio — ASS Renderer Boundary PROTOTYPE"
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 1_180, height: 720))
            window.minSize = NSSize(width: 980, height: 620)
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            self.controller = controller
            self.window = window
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
@MainActor
enum ASSRendererBoundaryPrototypeMain {
    private static var delegate: PrototypeAppDelegate?

    static func main() {
        NSWindow.allowsAutomaticWindowTabbing = false
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = PrototypeAppDelegate()
        self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}
