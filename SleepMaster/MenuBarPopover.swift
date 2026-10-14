import SwiftUI

struct MenuBarIcon: View {
    @Bindable var state: AppState

    var body: some View {
        HStack(spacing: 5) {
            menuSymbol
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(menuIconColor)
            if let label = state.menuBarLabel {
                Text(label)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(state.isPaused ? SleepTheme.menuBarMuted : SleepTheme.amber)
            }
        }
        .accessibilityLabel(menuAccessibilityLabel)
        .accessibilityValue(state.powerAccessibilityValue)
    }

    @ViewBuilder
    private var menuSymbol: some View {
        if state.isPaused {
            ZStack {
                Image(systemName: "eye")
                Image(systemName: "pause.fill")
                    .font(.system(size: 6, weight: .bold))
            }
        } else if state.isActive {
            Image(systemName: "eye")
        } else {
            Image(systemName: "moon")
        }
    }

    private var menuIconColor: Color {
        if state.isPaused {
            return SleepTheme.menuBarMuted
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
            appliesSection
            if state.helperNeedsApproval {
                Button("Approve in System Settings") {
                    state.openHelperApproval()
                }
                .buttonStyle(.plain)
                .foregroundStyle(SleepTheme.amber)
                .font(.system(size: 13, weight: .medium))
                .accessibilityLabel("Approve in System Settings")
            }
            SleepTheme.divider
                .frame(height: 1)
            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(SleepTheme.popoverBackground)
        .onAppear {
            state.refresh()
        }
        .onChange(of: state.statusTitle) { _, newValue in
            AccessibilityNotification.Announcement(newValue).post()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SleepTheme.iconWell)
                    .frame(width: 28, height: 28)
                Image(systemName: "moon")
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
            .keyboardShortcut(",", modifiers: .command)
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
            .accessibilityValue(state.powerAccessibilityValue)
            .accessibilityAddTraits(state.isActive ? [.isSelected] : [])
            .keyboardShortcut("s", modifiers: [.option, .command])

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
                        extendButton("+30 min") { state.extend(by: 30 * 60) }
                        extendButton("+1 hour") { state.extend(by: 60 * 60) }
                    }
                    .padding(.top, 6)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(state.statusTitle). \(state.statusSubtitle)")
            .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(SleepTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mode")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
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
                    .foregroundStyle(SleepTheme.footer)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(SleepTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Until a specific time")

                if showTimePicker {
                    DatePicker(
                        "Until",
                        selection: $specificTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .accessibilityLabel("Until time")
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

    private var appliesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Applies to both modes")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(SleepTheme.section)
                .padding(.bottom, 6)

            settingRow(
                title: "Only while plugged in",
                subtitle: state.plugInSubtitle,
                systemImage: "powerplug",
                iconTint: state.onlyWhilePluggedIn ? SleepTheme.amber : SleepTheme.muted,
                isOn: $state.onlyWhilePluggedIn,
                corners: .top
            )
            settingRow(
                title: "Let the display sleep",
                subtitle: "Screen turns off, apps keep running",
                systemImage: "sun.min",
                iconTint: state.allowDisplaySleep ? SleepTheme.amber : SleepTheme.muted,
                isOn: $state.allowDisplaySleep,
                corners: .bottom
            )
        }
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
            .accessibilityLabel("Settings")

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
            .accessibilityLabel("Quit Sleepmaster")
        }
    }

    private func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private enum CardCorners {
        case top
        case bottom
    }

    private func settingRow(
        title: String,
        subtitle: String,
        systemImage: String,
        iconTint: Color,
        isOn: Binding<Bool>,
        corners: CardCorners
    ) -> some View {
        let radii = corners == .top
            ? RectangleCornerRadii(topLeading: 10, bottomLeading: 2, bottomTrailing: 2, topTrailing: 10)
            : RectangleCornerRadii(topLeading: 2, bottomLeading: 10, bottomTrailing: 10, topTrailing: 2)
        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SleepTheme.iconWell)
                    .frame(width: 28, height: 28)
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconTint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SleepTheme.text)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SleepTheme.muted)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(SleepTheme.amber)
                .disabled(state.isBusy)
                .accessibilityLabel(title)
                .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SleepTheme.card, in: UnevenRoundedRectangle(cornerRadii: radii, style: .continuous))
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
        .accessibilityLabel(title)
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
        .accessibilityLabel(title)
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
            .accessibilityLabel(title)
    }
}
