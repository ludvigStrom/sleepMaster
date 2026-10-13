import AppKit
import SwiftUI

@main
struct SleepMasterApp: App {
    @StateObject private var sleepPreventer = SleepPreventer()

    init() {
        LoginItem.registerIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(sleepPreventer: sleepPreventer)
        } label: {
            Label(
                "SleepMaster",
                systemImage: sleepPreventer.isSleepDisabled ? "moon.zzz.fill" : "moon.zzz"
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var sleepPreventer: SleepPreventer

    var body: some View {
        Group {
            Toggle(
                "Do not go to sleep",
                isOn: Binding(
                    get: { sleepPreventer.isSleepDisabled },
                    set: { _ in sleepPreventer.toggle() }
                )
            )
            .disabled(sleepPreventer.isBusy)

            Text(sleepPreventer.statusText)

            if let errorMessage = sleepPreventer.errorMessage {
                Text(errorMessage)
            }

            Divider()

            Button("Quit SleepMaster") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .onAppear {
            sleepPreventer.refresh()
        }
    }
}
