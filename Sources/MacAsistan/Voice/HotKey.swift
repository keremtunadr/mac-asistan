import Carbon
import Foundation

/// Sistem genelinde çalışan klavye kısayolu (varsayılan ⌥ + Boşluk).
/// Carbon RegisterEventHotKey Erişilebilirlik izni gerektirmez.
final class HotKey {
    static let shared = HotKey()

    var handler: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    func register(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(optionKey)) {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKey.shared.handler?() }
            return noErr
        }, 1, &eventType, nil, &eventHandlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D41_5354), id: 1) // "MAST"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        hotKeyRef = nil
        eventHandlerRef = nil
    }
}
