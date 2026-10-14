import AppKit
import SwiftUI
import UserNotifications

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
    private var onboardingWindow: NSWindow?
    private let updater = SparkleUpdater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        UserNotificationClient.registerCategories()
        if NSClassFromString("XCTestCase") == nil {
            HelperClient.registerIfNeeded()
            appState.refresh()
            LegacySleepReset.offerIfNeeded()
            toggleHotKey = ToggleHotKey { [weak self] in
                self?.appState.toggle()
            }
            updater.start()
            showOnboardingIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        toggleHotKey?.stop()
        appState.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showOnboardingIfNeeded() {
        guard appState.needsOnboarding else { return }
        let view = OnboardingView(state: appState) { [weak self] in
            self?.appState.completeOnboarding()
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Sleepmaster"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.actionIdentifier
        await MainActor.run {
            appState.handleNotificationAction(identifier)
        }
    }
}
