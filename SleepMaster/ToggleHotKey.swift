import Carbon
import Foundation

@MainActor
final class ToggleHotKey {
    static let shortcutLabel = "⌥⌘S"

    private var hotKeyRef: EventHotKeyRef?
    private let center = HotKeyCenter.shared

    init(onToggle: @escaping () -> Void) {
        center.handler = onToggle
        center.installIfNeeded()

        var ref: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x534C504D, id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            UInt32(optionKey | cmdKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status != noErr {
            NSLog("SleepMaster: could not register toggle hotkey (%d)", status)
            return
        }
        hotKeyRef = ref
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if center.handler != nil {
            center.handler = nil
        }
    }
}

private final class HotKeyCenter: @unchecked Sendable {
    static let shared = HotKeyCenter()

    var handler: (() -> Void)?
    private var installed = false

    func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, nil)
    }
}

private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        HotKeyCenter.shared.handler?()
    }
    return noErr
}
