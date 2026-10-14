import SwiftUI

struct OnboardingView: View {
    @Bindable var state: AppState
    var onContinue: () -> Void
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SleepTheme.iconWell)
                        .frame(width: 36, height: 36)
                    Image(systemName: "moon")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SleepTheme.amber)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Sleepmaster")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SleepTheme.text)
                    Text("Keep the Mac awake from the menu bar.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(SleepTheme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                modeBlurb(
                    title: "Indefinitely",
                    body: "Stays awake until you turn it off or quit."
                )
                modeBlurb(
                    title: "Timer",
                    body: "Pick a duration or a time of day. Sleepmaster turns itself off when the time is up."
                )
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SleepTheme.text)
                    Text("Sleepmaster starts off after you log in.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(SleepTheme.muted)
                }
                Spacer(minLength: 8)
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(SleepTheme.amber)
                    .controlSize(.regular)
                    .fixedSize()
                    .accessibilityLabel("Launch at login")
                    .accessibilityValue(launchAtLogin ? "On" : "Off")
            }

            if let loginItemError {
                Text(loginItemError)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.red.opacity(0.9))
            }

            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SleepTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(SleepTheme.amber, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Continue")
        }
        .padding(28)
        .frame(width: 420)
        .background(SleepTheme.popoverBackground)
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

    private func modeBlurb(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SleepTheme.text)
            Text(body)
                .font(.system(size: 12.5))
                .foregroundStyle(SleepTheme.muted)
        }
        .accessibilityElement(children: .combine)
    }
}
