import Combine
import Foundation
import IOKit.ps

@MainActor
protocol PowerMonitoring: AnyObject {
    var isOnAC: Bool { get }
    var batteryPercent: Int? { get }
    func addChangeHandler(_ handler: @escaping () -> Void)
    func start()
}

@MainActor
final class PowerMonitor: PowerMonitoring {
    private(set) var isOnAC = true
    private(set) var batteryPercent: Int?

    private var changeHandlers: [() -> Void] = []
    private var runLoopSource: CFRunLoopSource?

    func addChangeHandler(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }

    func start() {
        refresh()
        guard runLoopSource == nil else { return }

        let opaque = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.refresh()
            }
        }, opaque)?.takeRetainedValue() else {
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    func refresh() {
        let snapshot = Self.read()
        let changed = snapshot.isOnAC != isOnAC || snapshot.batteryPercent != batteryPercent
        isOnAC = snapshot.isOnAC
        batteryPercent = snapshot.batteryPercent
        if changed {
            if let batteryPercent {
                NSLog("SleepMaster: power %@ %d%%", isOnAC ? "AC" : "battery", batteryPercent)
            } else {
                NSLog("SleepMaster: power %@", isOnAC ? "AC" : "battery")
            }
        }
        changeHandlers.forEach { $0() }
    }

    static func read() -> (isOnAC: Bool, batteryPercent: Int?) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return (true, nil)
        }

        var isOnAC = true
        var percent: Int?
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let state = description[kIOPSPowerSourceStateKey] as? String {
                isOnAC = state == kIOPSACPowerValue
            }
            if let capacity = description[kIOPSCurrentCapacityKey] as? Int {
                percent = capacity
            }
        }
        return (isOnAC, percent)
    }
}
