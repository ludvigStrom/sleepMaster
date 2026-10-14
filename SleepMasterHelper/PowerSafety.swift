import Foundation
import IOKit.ps

final class PowerSafety {
    private let onTrip: () -> Void
    private var source: CFRunLoopSource?
    private var tripped = false

    init(onTrip: @escaping () -> Void) {
        self.onTrip = onTrip
    }

    func start() {
        check()
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        guard let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerSafety>.fromOpaque(context).takeUnretainedValue().check()
        }, opaque)?.takeRetainedValue() else {
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .defaultMode)
        source = created
    }

    private func check() {
        let snapshot = readPower()
        let shouldTrip = LidClosedSafety.shouldDisableLidClosed(
            isOnAC: snapshot.isOnAC,
            batteryPercent: snapshot.batteryPercent
        )
        if shouldTrip, !tripped {
            tripped = true
            helperLog.info("battery \(snapshot.batteryPercent ?? -1, privacy: .public)% on battery; turning lid-closed off")
            onTrip()
        } else if !shouldTrip {
            tripped = false
        }
    }

    private func readPower() -> (isOnAC: Bool, batteryPercent: Int?) {
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
