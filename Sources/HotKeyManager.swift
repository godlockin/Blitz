import AppKit
import Carbon

typealias EventMods = NSEvent.ModifierFlags

enum HotKeyAction: UInt32 {
    case launcher = 1
    case clipboard = 2
    case snippets = 3
    case historyPopup = 4
    case settings = 5
    case clearHistory = 6
    case editSnippets = 7
    case mainMenu = 8
}

/// Multiple global hotkeys via Carbon + NSEvent monitors.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onAction: ((HotKeyAction) -> Void)?
    /// Snippet folder hotkeys (folder id).
    var onSnippetFolder: ((String) -> Void)?

    private struct Binding {
        let action: HotKeyAction
        var keyCode: UInt32
        var modifiers: UInt32
        var carbonRef: EventHotKeyRef?
    }

    private var bindings: [HotKeyAction: Binding] = [:]
    private var folderRefs: [(id: UInt32, folderId: String, ref: EventHotKeyRef?)] = []
    private var folderIdByHotKeyID: [UInt32: String] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastFireAt = Date.distantPast
    private var lastFireAction: HotKeyAction?
    private(set) var lastStatus: OSStatus = noErr
    private(set) var statusMessage = ""

    func unregister() {
        for key in bindings.keys {
            if let ref = bindings[key]?.carbonRef {
                UnregisterEventHotKey(ref)
            }
            bindings[key]?.carbonRef = nil
        }
        bindings.removeAll()
        for entry in folderRefs {
            if let ref = entry.ref { UnregisterEventHotKey(ref) }
        }
        folderRefs.removeAll()
        folderIdByHotKeyID.removeAll()
        removeMonitors()
    }

    @discardableResult
    func register(autoFallback: Bool = true) -> Bool {
        unregister()
        ensureCarbonHandler()

        let store = SettingsStore.shared
        var launcherCode = store.hotKeyCode
        var launcherMods = store.hotKeyModifiers
        if launcherCode == UInt32(kVK_Space) && launcherMods == UInt32(optionKey) {
            launcherCode = UInt32(kVK_Space)
            launcherMods = UInt32(controlKey | optionKey)
            store.hotKeyCode = launcherCode
            store.hotKeyModifiers = launcherMods
        }

        var okLauncher = registerOne(action: .launcher, keyCode: launcherCode, modifiers: launcherMods)
        if !okLauncher && autoFallback {
            for (fbCode, fbMods) in [
                (UInt32(kVK_Space), UInt32(controlKey | optionKey)),
                (UInt32(kVK_Space), UInt32(cmdKey | optionKey)),
            ] as [(UInt32, UInt32)] {
                if registerOne(action: .launcher, keyCode: fbCode, modifiers: fbMods) {
                    store.hotKeyCode = fbCode
                    store.hotKeyModifiers = fbMods
                    okLauncher = true
                    break
                }
            }
        }

        var okClip = registerOne(action: .clipboard, keyCode: store.clipboardHotKeyCode, modifiers: store.clipboardHotKeyModifiers)
        if !okClip && autoFallback {
            for (fbCode, fbMods) in [
                (UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey)),
                (UInt32(kVK_ANSI_V), UInt32(cmdKey | optionKey)),
            ] as [(UInt32, UInt32)] {
                if registerOne(action: .clipboard, keyCode: fbCode, modifiers: fbMods) {
                    store.clipboardHotKeyCode = fbCode
                    store.clipboardHotKeyModifiers = fbMods
                    okClip = true
                    break
                }
            }
        }

        var okSnip = registerOne(action: .snippets, keyCode: store.snippetsHotKeyCode, modifiers: store.snippetsHotKeyModifiers)
        if !okSnip && autoFallback {
            for (fbCode, fbMods) in [
                (UInt32(kVK_ANSI_B), UInt32(shiftKey | cmdKey)),
                (UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey)),
            ] as [(UInt32, UInt32)] {
                if registerOne(action: .snippets, keyCode: fbCode, modifiers: fbMods) {
                    store.snippetsHotKeyCode = fbCode
                    store.snippetsHotKeyModifiers = fbMods
                    okSnip = true
                    break
                }
            }
        }

        // Clipy-style popup menus — try defaults, then non-colliding fallbacks
        var mainCode = store.mainMenuHotKeyCode
        var mainMods = store.mainMenuHotKeyModifiers
        if mainCode == store.clipboardHotKeyCode && mainMods == store.clipboardHotKeyModifiers {
            mainCode = UInt32(kVK_ANSI_V)
            mainMods = UInt32(optionKey | cmdKey)
            store.mainMenuHotKeyCode = mainCode
            store.mainMenuHotKeyModifiers = mainMods
        }
        if !registerOne(action: .mainMenu, keyCode: mainCode, modifiers: mainMods) {
            for (c, m) in [
                (UInt32(kVK_ANSI_V), UInt32(optionKey | cmdKey)),
                (UInt32(kVK_ANSI_M), UInt32(controlKey | optionKey)),
            ] as [(UInt32, UInt32)] {
                if registerOne(action: .mainMenu, keyCode: c, modifiers: m) {
                    store.mainMenuHotKeyCode = c
                    store.mainMenuHotKeyModifiers = m
                    break
                }
            }
        }
        _ = registerOne(action: .historyPopup, keyCode: store.historyPopupHotKeyCode, modifiers: store.historyPopupHotKeyModifiers)
        _ = registerOne(action: .settings, keyCode: store.settingsHotKeyCode, modifiers: store.settingsHotKeyModifiers)

        if store.clearHistoryHotKeyCode != 0, store.clearHistoryHotKeyModifiers != 0 {
            _ = registerOne(action: .clearHistory, keyCode: store.clearHistoryHotKeyCode, modifiers: store.clearHistoryHotKeyModifiers)
        }
        if store.editSnippetsHotKeyCode != 0, store.editSnippetsHotKeyModifiers != 0 {
            _ = registerOne(action: .editSnippets, keyCode: store.editSnippetsHotKeyCode, modifiers: store.editSnippetsHotKeyModifiers)
        }

        registerFolderHotKeys()
        installEventMonitors()

        lastStatus = (okLauncher || okClip || okSnip) ? noErr : -1
        statusMessage = "Launcher \(store.hotKeyDisplayString) · Clip \(store.clipboardHotKeyDisplayString) · Main \(store.mainMenuHotKeyDisplayString) · Hist \(store.historyPopupHotKeyDisplayString)"
        FileLogger.log("hotkeys ready — \(statusMessage)")
        return okLauncher || okClip || okSnip
    }

    private func registerFolderHotKeys() {
        var nextID: UInt32 = 100
        for folder in SnippetStore.shared.folders {
            guard let code = folder.hotKeyCode, let mods = folder.hotKeyModifiers, mods != 0 else { continue }
            let hotKeyID = EventHotKeyID(signature: OSType(0x46524745), id: nextID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(code, mods, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr {
                folderRefs.append((id: nextID, folderId: folder.id, ref: ref))
                folderIdByHotKeyID[nextID] = folder.id
            }
            nextID += 1
        }
    }

    private func registerOne(action: HotKeyAction, keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard modifiers != 0 else { return false }
        let hotKeyID = EventHotKeyID(signature: OSType(0x46524745), id: action.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        bindings[action] = Binding(action: action, keyCode: keyCode, modifiers: modifiers, carbonRef: status == noErr ? ref : nil)
        return status == noErr
    }

    private func fire(_ action: HotKeyAction) {
        let now = Date()
        if lastFireAction == action, now.timeIntervalSince(lastFireAt) < 0.25 { return }
        lastFireAt = now
        lastFireAction = action
        FileLogger.log("hotkey fired \(action)")
        onAction?(action)
    }

    private func fireFolder(_ folderId: String) {
        let now = Date()
        if now.timeIntervalSince(lastFireAt) < 0.25 { return }
        lastFireAt = now
        FileLogger.log("hotkey fired folder \(folderId)")
        onSnippetFolder?(folderId)
    }

    private func ensureCarbonHandler() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, theEvent, userData) -> OSStatus in
                guard let userData, let theEvent else { return noErr }
                var hk = EventHotKeyID()
                let err = GetEventParameter(
                    theEvent,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hk
                )
                guard err == noErr else { return noErr }
                let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                if let action = HotKeyAction(rawValue: hk.id) {
                    DispatchQueue.main.async { mgr.fire(action) }
                } else if let folderId = mgr.folderIdByHotKeyID[hk.id] {
                    DispatchQueue.main.async { mgr.fireFolder(folderId) }
                }
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
    }

    private func installEventMonitors() {
        removeMonitors()
        let snapshot = bindings
        var folderCombos: [(UInt32, UInt32, String)] = []
        for folder in SnippetStore.shared.folders {
            if let c = folder.hotKeyCode, let m = folder.hotKeyModifiers, m != 0 {
                folderCombos.append((c, m, folder.id))
            }
        }

        let match: (NSEvent) -> HotKeyAction? = { event in
            let pressed = event.modifierFlags.intersection([.command, .option, .control, .shift])
            for (_, b) in snapshot {
                let need = HotKeyManager.nsModifiers(fromCarbon: b.modifiers)
                if UInt32(event.keyCode) == b.keyCode && pressed == need {
                    return b.action
                }
            }
            return nil
        }

        let matchFolder: (NSEvent) -> String? = { event in
            let pressed = event.modifierFlags.intersection([.command, .option, .control, .shift])
            for (code, mods, fid) in folderCombos {
                if UInt32(event.keyCode) == code && pressed == HotKeyManager.nsModifiers(fromCarbon: mods) {
                    return fid
                }
            }
            return nil
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let action = match(event) {
                DispatchQueue.main.async { self?.fire(action) }
                return nil
            }
            if let fid = matchFolder(event) {
                DispatchQueue.main.async { self?.fireFolder(fid) }
                return nil
            }
            return event
        }

        if Accessibility.trusted {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if let action = match(event) {
                    DispatchQueue.main.async { self?.fire(action) }
                } else if let fid = matchFolder(event) {
                    DispatchQueue.main.async { self?.fireFolder(fid) }
                }
            }
        }
    }

    static func nsModifiers(fromCarbon carbon: UInt32) -> EventMods {
        var flags = NSEvent.ModifierFlags(rawValue: 0)
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }
}
