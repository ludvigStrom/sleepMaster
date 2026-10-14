enum BatteryFloor {
    static let defaultPercent = 20

    static func shouldAllowSleep(
        isOnAC: Bool,
        batteryPercent: Int?,
        floor: Int = defaultPercent
    ) -> Bool {
        guard !isOnAC, let batteryPercent else { return false }
        return batteryPercent < floor
    }
}
