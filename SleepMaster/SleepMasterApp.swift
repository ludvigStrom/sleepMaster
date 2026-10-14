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
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.registerIfNeeded()
        if NSClassFromString("XCTestCase") == nil {
            HelperClient.registerIfNeeded()
            appState.refresh()
            LegacySleepReset.offerIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stop()
    }
}
