enum LidClosedSafety {
    static let defaultCutoffPercent = 10

    static func shouldDisableLidClosed(
        isOnAC: Bool,
        batteryPercent: Int?,
        cutoff: Int = defaultCutoffPercent
    ) -> Bool {
        guard !isOnAC, let batteryPercent else { return false }
        return batteryPercent < cutoff
    }
}
