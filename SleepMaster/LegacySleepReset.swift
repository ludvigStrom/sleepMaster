import AppKit

enum LegacySleepReset {
    @MainActor
    static func offerIfNeeded() {
        guard PmsetSleepController.readSleepDisabled() else { return }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Reset the old sleep setting?"
        alert.informativeText = "An earlier version of Sleepmaster disabled sleep for the whole Mac. Resetting it asks for your password once."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Not Now")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try PmsetSleepController().stop()
        } catch {
            if SleepControlError.isUserCanceled(error) {
                return
            }
            NSAlert(error: error).runModal()
        }
    }
}
