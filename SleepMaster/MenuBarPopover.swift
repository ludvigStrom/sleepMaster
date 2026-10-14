import SwiftUI

struct MenuBarIcon: View {
    @Bindable var state: AppState

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.isActive ? "eye.fill" : "moon.fill")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(menuIconColor)
            if let label = state.menuBarLabel {
                Text(label)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(state.isPaused ? SleepTheme.muted : SleepTheme.amber)
            }
        }
        .accessibilityLabel(menuAccessibilityLabel)
    }

    private var menuIconColor: Color {
        if state.isPaused {
            return SleepTheme.muted
        }
        return state.isActive ? SleepTheme.amber : Color.primary
    }

    private var menuAccessibilityLabel: String {
        if state.isPaused {
            return "Sleepmaster paused"
        }
        if let label = state.countdownMenuLabel {
            return "Sleepmaster on, \(label) remaining"
        }
        return state.isActive ? "Sleepmaster on" : "Sleepmaster off"
    }
}

struct MenuBarPopover: View {
    @Bindable var state: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var showTimePicker = false
    @State private var specificTime = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            powerCard
            modeSection
            lidClosedRow
            plugOnlyRow
            displaySleepRow
            if state.helperNeedsApproval {
                Button("Approve in System Settings") {
                    state.openHelperApproval()
                }
                .buttonStyle(.plain)
                .foregroundStyle(SleepTheme.amber)
                .font(.system(size: 13, weight: .medium))
            }
            SleepTheme.divider
                .frame(height: 1)
            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(SleepTheme.popoverBackground)
        .preferredColorScheme(.dark)
        .onAppear {
            state.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SleepTheme.iconWell)
                    .frame(width: 28, height: 28)
                Image(systemName: "moon.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SleepTheme.amber)
            }
            Text("Sleepmaster")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SleepTheme.text)
            Spacer()
            Button {
                openSettingsWindow()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SleepTheme.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var powerCard: some View {
        HStack(alignment: .center, spacing: 16) {
            Button {
                state.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(state.isActive && !state.isPaused ? SleepTheme.amber : SleepTheme.iconWell)
                    Circle()
                        .stroke(state.isActive ? SleepTheme.amber : SleepTheme.powerBorder, lineWidth: 2)
                    Image(systemName: "power")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(powerIconColor)
                }
                .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            .disabled(state.isBusy)
            .accessibilityLabel("Keep Mac awake")
            .accessibilityAddTraits(state.isActive ? [.isSelected] : [])

            VStack(alignment: .leading, spacing: 4) {
                Text(state.statusTitle)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(SleepTheme.text)
                Text(state.statusSubtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(SleepTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if state.showExtendButtons {
                    HStack(spacing: 6) {
                        extendButton(" +30 min ") { state.extend(by: 30 * 60) }
                        extendButton(" +1 hour ") { state.extend(by: 60 * 60) }
                    }
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(SleepTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MODE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(SleepTheme.section)

            HStack(spacing: 4) {
                modeButton("Indefinitely", selected: state.mode == .indefinitely) {
                    state.mode = .indefinitely
                }
                modeButton("Timer", selected: state.mode == .timer) {
                    state.mode = .timer
                }
            }
            .padding(3)
            .background(SleepTheme.iconWell, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mode")

            if state.mode == .timer {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(TimerDurations.chips, id: \.seconds) { chip in
                        chipButton(chip.label, selected: state.selectedDuration == chip.seconds) {
                            state.selectDuration(chip.seconds)
                        }
                    }
                }

                Button {
                    showTimePicker.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 13, weight: .medium))
                        Text("Until a specific time…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.839, green: 0.843, blue: 0.863))
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(SleepTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                if showTimePicker {
                    DatePicker(
                        "Until",
                        selection: $specificTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .onChange(of: specificTime) { _, newValue in
                        let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        state.setUntil(hour: components.hour ?? 0, minute: components.minute ?? 0)
                    }
                }
            } else {
                Text("Stays awake until you turn it off or quit Sleepmaster.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(SleepTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var lidClosedRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SleepTheme.iconWell)
                    .frame(width: 28, height: 28)
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.lidClosedEnabled ? SleepTheme.amber : SleepTheme.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Stay awake with the lid closed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SleepTheme.text)
                Text("Closing the lid keeps the Mac awake")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SleepTheme.muted)
            }
            Spacer(minLength: 8)
            Toggle("Stay awake with the lid closed", isOn: $state.lidClosedEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(SleepTheme.amber)
                .disabled(state.isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SleepTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var plugOnlyRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SleepTheme.iconWell)
                    .frame(width: 28, height: 28)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.onlyWhilePluggedIn ? SleepTheme.amber : SleepTheme.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Only while plugged in")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SleepTheme.text)
                Text(state.plugInSubtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SleepTheme.muted)
            }
            Spacer(minLength: 8)
            Toggle("Only while plugged in", isOn: $state.onlyWhilePluggedIn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(SleepTheme.amber)
                .disabled(state.isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SleepTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var displaySleepRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SleepTheme.iconWell)
                    .frame(width: 28, height: 28)
                Image(systemName: "sun.min")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.allowDisplaySleep ? SleepTheme.amber : SleepTheme.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Let the display sleep")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SleepTheme.text)
                Text("The screen can turn off; the Mac stays awake")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SleepTheme.muted)
            }
            Spacer(minLength: 8)
            Toggle("Let the display sleep", isOn: $state.allowDisplaySleep)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(SleepTheme.amber)
                .disabled(state.isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SleepTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var powerIconColor: Color {
        if state.isPaused {
            return SleepTheme.amber
        }
        return state.isActive ? SleepTheme.ink : SleepTheme.muted
    }

    private var footer: some View {
        HStack {
            Button("Settings…") {
                openSettingsWindow()
            }
            .buttonStyle(.plain)
            .foregroundStyle(SleepTheme.footer)
            .font(.system(size: 13))

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 10) {
                    Text("Quit")
                    Text("⌘Q")
                        .foregroundStyle(SleepTheme.section)
                }
                .font(.system(size: 13))
                .foregroundStyle(SleepTheme.footer)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
    }

    private func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func modeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
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

    private func chipButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? SleepTheme.ink : SleepTheme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(selected ? SleepTheme.amber : SleepTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? SleepTheme.amber : SleepTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func extendButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SleepTheme.text)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(SleepTheme.iconWell, in: Capsule())
            .overlay(Capsule().stroke(SleepTheme.powerBorder, lineWidth: 1))
            .buttonStyle(.plain)
    }
}
