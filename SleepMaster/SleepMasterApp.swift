import AppKit
import SwiftUI

@main
struct SleepMasterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(state: appDelegate.appState)
        } label: {
            MenuBarIcon(state: appDelegate.appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: appDelegate.appState)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var toggleHotKey: ToggleHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSClassFromString("XCTestCase") == nil {
            HelperClient.registerIfNeeded()
            appState.refresh()
            LegacySleepReset.offerIfNeeded()
            toggleHotKey = ToggleHotKey { [weak self] in
                self?.appState.toggle()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        toggleHotKey?.stop()
        appState.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
