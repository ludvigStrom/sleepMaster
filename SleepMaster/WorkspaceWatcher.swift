import AppKit
import Foundation

@MainActor
protocol WorkspaceWatching: AnyObject {
    var runningBundleIDs: Set<String> { get }
    func displayName(for bundleID: String) -> String
    func addChangeHandler(_ handler: @escaping () -> Void)
    func start()
}

@MainActor
final class IdleWorkspace: WorkspaceWatching {
    var runningBundleIDs: Set<String> = []
    func displayName(for bundleID: String) -> String { bundleID }
    func addChangeHandler(_ handler: @escaping () -> Void) {}
    func start() {}
}

@MainActor
final class WorkspaceWatcher: WorkspaceWatching {
    private var changeHandlers: [() -> Void] = []
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    var runningBundleIDs: Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url)
        {
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
                return name
            }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
                return name
            }
        }
        return bundleID
    }

    func addChangeHandler(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }

    func start() {
        guard launchObserver == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.changeHandlers.forEach { $0() }
            }
        }
        terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.changeHandlers.forEach { $0() }
            }
        }
    }
}
