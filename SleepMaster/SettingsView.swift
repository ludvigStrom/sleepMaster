import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                groupedSection("General") {
                    pickerRow(
                        title: "Appearance",
                        showDivider: true
                    ) {
                        Picker("Appearance", selection: $state.appearancePreference) {
                            Text("Light").tag(AppearancePreference.light)
                            Text("Dark").tag(AppearancePreference.dark)
                            Text("Follow OS").tag(AppearancePreference.system)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(maxWidth: 260)
                        .accessibilityLabel("Appearance")
                    }
                    toggleRow(
                        title: "Launch at login",
                        isOn: launchAtLoginBinding,
                        showDivider: true
                    )
                    if let loginItemError {
                        Text(loginItemError)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.red.opacity(0.9))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                    }
                    toggleRow(
                        title: "Show time left in menu bar",
                        subtitle: "e.g. “1:42” next to the icon in Timer mode",
                        isOn: $state.showTimeInMenuBar,
                        showDivider: true
                    )
                    valueRow(
                        title: "Toggle shortcut",
                        subtitle: "Works from any app",
                        value: ToggleHotKey.shortcutLabel,
                        showDivider: false
                    )
                }

                groupedSection("When turned on") {
                    pickerRow(
                        title: "Default mode",
                        showDivider: true
                    ) {
                        Picker("Default mode", selection: $state.defaultMode) {
                            Text("Indefinitely").tag(SleepMode.indefinitely)
                            Text("Timer").tag(SleepMode.timer)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(SleepTheme.text)
                    }
                    if state.defaultMode == .timer {
                        pickerRow(title: "Default timer", showDivider: true) {
                            Picker("Default timer", selection: $state.defaultDuration) {
                                ForEach(TimerDurations.chips, id: \.seconds) { chip in
                                    Text(chip.label).tag(chip.seconds)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .tint(SleepTheme.text)
                        }
                    }
                    toggleRow(
                        title: "Remember my last choice",
                        subtitle: "Overrides the defaults above",
                        isOn: $state.rememberLastChoice,
                        showDivider: false
                    )
                }

                groupedSection("Power & battery") {
                    toggleRow(
                        title: "Only while plugged in",
                        subtitle: "Pauses on battery, resumes on power. Also in the menu.",
                        isOn: $state.onlyWhilePluggedIn,
                        showDivider: true
                    )
                    toggleRow(
                        title: "Turn on automatically when plugged in",
                        subtitle: "Connecting power starts Indefinitely mode",
                        isOn: $state.autoOnWhenPluggedIn,
                        showDivider: true
                    )
                    stepperRow(
                        title: "Allow sleep when battery is below",
                        subtitle: "Safety net when “Only while plugged in” is off",
                        value: $state.batteryFloorPercent,
                        range: 5...50,
                        format: { "\($0) %" },
                        showDivider: true
                    )
                    toggleRow(
                        title: "Stay awake with the lid closed",
                        subtitle: "Requires power and an external display",
                        isOn: $state.lidClosedEnabled,
                        showDivider: false
                    )
                }

                groupedSection("Automation") {
                    watchedAppsBlock
                    divider
                    toggleRow(
                        title: "Schedule",
                        subtitle: state.scheduleSummary,
                        isOn: $state.scheduleEnabled,
                        showDivider: state.scheduleEnabled
                    )
                    if state.scheduleEnabled {
                        scheduleEditor
                    }
                }

                groupedSection("Notifications") {
                    stepperRow(
                        title: "Warn before the timer ends",
                        subtitle: "With a one-click “+30 min”",
                        value: Binding(
                            get: { Int(state.timerWarningLead / 60) },
                            set: { state.timerWarningLead = TimeInterval($0 * 60) }
                        ),
                        range: 1...15,
                        format: { "\($0) min before" },
                        showDivider: true
                    )
                    toggleRow(
                        title: "Notify when paused on battery",
                        isOn: $state.notifyOnBatteryPause,
                        showDivider: false
                    )
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .frame(minWidth: 520, idealWidth: 540, minHeight: 480)
        .background(SleepTheme.popoverBackground)
        .preferredColorScheme(state.appearancePreference.colorScheme)
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
                    launchAtLogin = newValue
                    loginItemError = nil
                } catch {
                    launchAtLogin = LoginItem.isEnabled
                    loginItemError = error.localizedDescription
                }
            }
        )
    }

    private var watchedAppsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep awake for these apps")
                    .font(.system(size: 13))
                    .foregroundStyle(SleepTheme.text)
                Text("Sleep is allowed when busy apps go idle and running apps quit.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SleepTheme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(state.watchedApps) { app in
                divider
                HStack(alignment: .center, spacing: 10) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(SleepTheme.iconWell)
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(state.displayName(forBundleID: app.bundleID))
                                .font(.system(size: 13))
                                .foregroundStyle(SleepTheme.text)
                            if let snapshot = state.snapshot(forBundleID: app.bundleID) {
                                Text("\(snapshot.liveStatusLabel) · \(snapshot.cpuLabel)")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(snapshot.isKeepingAwake ? SleepTheme.amber : SleepTheme.muted)
                            }
                        }
                        Picker(
                            "Keep awake mode for \(state.displayName(forBundleID: app.bundleID))",
                            selection: Binding(
                                get: {
                                    state.watchedApps.first(where: { $0.bundleID == app.bundleID })?.mode ?? app.mode
                                },
                                set: { state.setWatchedAppMode($0, for: app.bundleID) }
                            )
                        ) {
                            Text("While running").tag(WatchedAppMode.whileRunning)
                            Text("While busy").tag(WatchedAppMode.whileBusy)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    Spacer(minLength: 8)
                    Button {
                        state.removeWatchedApp(bundleID: app.bundleID)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(SleepTheme.muted)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(state.displayName(forBundleID: app.bundleID))")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            divider
            stepperRow(
                title: "Busy when CPU is over",
                subtitle: "Of one core, for apps set to While busy",
                value: $state.busyCPUThresholdPercent,
                range: 5...80,
                format: { "\($0)%" },
                showDivider: true
            )
            Button("Add app…") {
                pickApplication()
            }
            .font(.system(size: 13))
            .foregroundStyle(SleepTheme.text)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(SleepTheme.powerBorder, lineWidth: 1)
                    .background(SleepTheme.iconWell, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            )
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .accessibilityLabel("Add app")
        }
    }

    private var scheduleEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { day in
                    dayChip(day)
                }
            }
            HStack {
                Text("From")
                    .font(.system(size: 13))
                    .foregroundStyle(SleepTheme.text)
                DatePicker(
                    "From",
                    selection: minutesDateBinding(
                        get: { state.scheduleStartMinutes },
                        set: { state.scheduleStartMinutes = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .tint(SleepTheme.amber)
                .accessibilityLabel("Schedule start")
                Spacer()
                Text("To")
                    .font(.system(size: 13))
                    .foregroundStyle(SleepTheme.text)
                DatePicker(
                    "To",
                    selection: minutesDateBinding(
                        get: { state.scheduleEndMinutes },
                        set: { state.scheduleEndMinutes = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .tint(SleepTheme.amber)
                .accessibilityLabel("Schedule end")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func dayChip(_ day: Int) -> some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let title = symbols.indices.contains(day - 1) ? symbols[day - 1] : "\(day)"
        let selected = state.scheduleDays.contains(day)
        return Button {
            var days = state.scheduleDays
            if selected {
                days.remove(day)
            } else {
                days.insert(day)
            }
            state.scheduleDays = days
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? SleepTheme.text : SleepTheme.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(selected ? SleepTheme.segmentOn : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weekdayAccessibilityLabel(day))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func weekdayAccessibilityLabel(_ day: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        guard symbols.indices.contains(day - 1) else { return "Day \(day)" }
        return symbols[day - 1]
    }

    private func minutesDateBinding(get: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.year = 2001
                components.month = 1
                components.day = 1
                components.hour = get() / 60
                components.minute = get() % 60
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let hour = Calendar.current.component(.hour, from: date)
                let minute = Calendar.current.component(.minute, from: date)
                set(hour * 60 + minute)
            }
        )
    }

    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an app to watch"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundle = Bundle(url: url)
        if let bundleID = bundle?.bundleIdentifier {
            state.addWatchedApp(bundleID: bundleID)
        }
    }

    private var divider: some View {
        SleepTheme.divider
            .frame(height: 1)
    }

    private func groupedSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SleepTheme.footer)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(SleepTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func toggleRow(title: String, subtitle: String? = nil, isOn: Binding<Bool>, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(SleepTheme.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(SleepTheme.muted)
                    }
                }
                Spacer(minLength: 8)
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SleepTheme.amber)
                    .controlSize(.regular)
                    .fixedSize()
                    .accessibilityLabel(title)
                    .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            if showDivider { divider }
        }
    }

    private func valueRow(title: String, subtitle: String, value: String, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(SleepTheme.text)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(SleepTheme.muted)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                Text(value)
                    .font(.system(size: 13).monospaced())
                    .foregroundStyle(SleepTheme.text)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(SleepTheme.iconWell, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(SleepTheme.powerBorder, lineWidth: 1)
                    )
                    .accessibilityLabel(title)
                    .accessibilityValue(value)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            if showDivider { divider }
        }
    }

    private func pickerRow<Content: View>(title: String, showDivider: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(SleepTheme.text)
                Spacer()
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            if showDivider { divider }
        }
    }

    private func stepperRow(
        title: String,
        subtitle: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        format: @escaping (Int) -> String,
        showDivider: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(SleepTheme.text)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(SleepTheme.muted)
                }
                Spacer()
                Stepper(value: value, in: range) {
                    Text(format(value.wrappedValue))
                        .font(.system(size: 13))
                        .foregroundStyle(SleepTheme.text)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(SleepTheme.iconWell, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(SleepTheme.powerBorder, lineWidth: 1)
                        )
                }
                .tint(SleepTheme.amber)
                .accessibilityLabel(title)
                .accessibilityValue(format(value.wrappedValue))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            if showDivider { divider }
        }
    }
}
