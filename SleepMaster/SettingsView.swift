import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("GENERAL") {
                    settingsToggle(
                        title: "Launch at login",
                        subtitle: "Sleepmaster starts off after you log in.",
                        isOn: launchAtLoginBinding
                    )
                    if let loginItemError {
                        Text(loginItemError)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.red.opacity(0.9))
                    }
                    settingsToggle(
                        title: "Show time in menu bar",
                        subtitle: "Hide the countdown next to the icon.",
                        isOn: $state.showTimeInMenuBar
                    )
                    shortcutRow
                    defaultModeRow
                    if state.defaultMode == .timer {
                        defaultDurationRow
                    }
                    settingsToggle(
                        title: "Remember last choice",
                        subtitle: "If off, each launch uses the defaults above.",
                        isOn: $state.rememberLastChoice
                    )
                    warningLeadRow
                }

                section("WHEN TURNED ON") {
                    settingsToggle(
                        title: "Only while plugged in",
                        subtitle: "Pause keep-awake on battery.",
                        isOn: $state.onlyWhilePluggedIn
                    )
                    settingsToggle(
                        title: "Notify when paused on battery",
                        subtitle: "One banner when keep-awake pauses.",
                        isOn: $state.notifyOnBatteryPause
                    )
                    batteryFloorRow
                    settingsToggle(
                        title: "Let the display sleep",
                        subtitle: "The screen can turn off; the Mac stays awake.",
                        isOn: $state.allowDisplaySleep
                    )
                    settingsToggle(
                        title: "Stay awake with the lid closed",
                        subtitle: "Closing the lid keeps the Mac awake.",
                        isOn: $state.lidClosedEnabled
                    )
                }
            }
            .padding(20)
        }
        .frame(minWidth: 420, idealWidth: 420, minHeight: 420)
        .background(SleepTheme.popoverBackground)
        .preferredColorScheme(.dark)
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    try LoginItem.setEnabled(newValue)
                    launchAtLogin = LoginItem.isEnabled
                    loginItemError = nil
                } catch {
                    launchAtLogin = LoginItem.isEnabled
                    loginItemError = error.localizedDescription
                }
            }
        )
    }

    private var shortcutRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Toggle Sleepmaster")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SleepTheme.text)
                Text("Works while another app is focused.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SleepTheme.muted)
            }
            Spacer()
            Text(ToggleHotKey.shortcutLabel)
                .font(.system(size: 13, weight: .medium).monospaced())
                .foregroundStyle(SleepTheme.footer)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SleepTheme.iconWell, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var defaultModeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default mode")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SleepTheme.text)
            HStack(spacing: 4) {
                modeChip("Indefinitely", selected: state.defaultMode == .indefinitely) {
                    state.defaultMode = .indefinitely
                }
                modeChip("Timer", selected: state.defaultMode == .timer) {
                    state.defaultMode = .timer
                }
            }
            .padding(3)
            .background(SleepTheme.iconWell, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var defaultDurationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default timer")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SleepTheme.text)
            Picker("Default timer", selection: $state.defaultDuration) {
                ForEach(TimerDurations.chips, id: \.seconds) { chip in
                    Text(chip.label).tag(chip.seconds)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(SleepTheme.amber)
        }
    }

    private var warningLeadRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Timer warning")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SleepTheme.text)
                Text("Notify this many minutes before the end.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SleepTheme.muted)
            }
            Spacer()
            Stepper(
                value: Binding(
                    get: { Int(state.timerWarningLead / 60) },
                    set: { state.timerWarningLead = TimeInterval($0 * 60) }
                ),
                in: 1...15
            ) {
                Text("\(Int(state.timerWarningLead / 60)) min")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(SleepTheme.text)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .tint(SleepTheme.amber)
        }
    }

    private var batteryFloorRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Battery floor")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SleepTheme.text)
                Text("Allow sleep below this level on battery.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SleepTheme.muted)
            }
            Spacer()
            Stepper(value: $state.batteryFloorPercent, in: 5...50) {
                Text("\(state.batteryFloorPercent)%")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(SleepTheme.text)
                    .frame(minWidth: 36, alignment: .trailing)
            }
            .tint(SleepTheme.amber)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(SleepTheme.section)
            content()
        }
    }

    private func settingsToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SleepTheme.text)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SleepTheme.muted)
            }
        }
        .toggleStyle(.switch)
        .tint(SleepTheme.amber)
    }

    private func modeChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.white : SleepTheme.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(selected ? SleepTheme.segmentOn : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
