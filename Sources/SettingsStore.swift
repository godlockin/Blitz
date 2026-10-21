import AppKit
import Carbon
import Foundation

/// Persisted preferences for Blitz (hotkey, clipboard, search, UI).
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private init() {}

    private enum Key {
        static let hotKeyCode = "blitz.hotKey.keyCode"
        static let hotKeyModifiers = "blitz.hotKey.modifiers"
        static let clipboardHotKeyCode = "blitz.clipboard.hotKey.keyCode"
        static let clipboardHotKeyModifiers = "blitz.clipboard.hotKey.modifiers"
        static let snippetsHotKeyCode = "blitz.snippets.hotKey.keyCode"
        static let snippetsHotKeyModifiers = "blitz.snippets.hotKey.modifiers"
        static let clipboardMax = "blitz.clipboard.maxItems"
        static let fileSearchLimit = "blitz.search.fileLimit"
        static let panelWidth = "blitz.panel.width"
        static let panelHeight = "blitz.panel.height"
        static let didOpenSettings = "blitz.settings.didOpenOnce"
        static let showWelcome = "blitz.settings.showWelcomeOnLaunch"
        static let pasteboardTypes = "blitz.clipboard.typeSettings"
        static let excludedApps = "blitz.clipboard.excludedBundleIDs"
        static let ignoreConcealed = "blitz.clipboard.ignoreConcealed"
        static let ignoreUniversal = "blitz.clipboard.ignoreUniversal"
        static let overwriteSame = "blitz.clipboard.overwriteSame"
        static let copySame = "blitz.clipboard.copySame"
        static let reorderAfterPaste = "blitz.clipboard.reorderAfterPaste"
        static let clearOnQuit = "blitz.clipboard.clearOnQuit"
        static let clearPeriodically = "blitz.clipboard.clearPeriodically"
        static let clearInterval = "blitz.clipboard.clearInterval"
        static let alertBeforeClear = "blitz.clipboard.alertBeforeClear"
        static let observeScreenshots = "blitz.clipboard.observeScreenshots"
        static let showColorPreview = "blitz.clipboard.showColorPreview"
        static let menuHistoryCount = "blitz.clipboard.menuHistoryCount"
        static let showNumbersInMenu = "blitz.clipboard.showNumbersInMenu"
        static let pastePlainMod = "blitz.clipboard.pastePlainEnabled"
        static let pastePlainKey = "blitz.clipboard.pastePlainModifier"
        static let deleteHistMod = "blitz.clipboard.deleteHistoryEnabled"
        static let deleteHistKey = "blitz.clipboard.deleteHistoryModifier"
        static let pasteDeleteMod = "blitz.clipboard.pasteAndDeleteEnabled"
        static let pasteDeleteKey = "blitz.clipboard.pasteAndDeleteModifier"
        // Menu (Clipy MenuSettings)
        static let inlineMenuLimit = "blitz.menu.inlineLimit"
        static let folderMenuLimit = "blitz.menu.folderLimit"
        static let maxMenuTitle = "blitz.menu.maxTitleLength"
        static let startsAtZero = "blitz.menu.startsAtZero"
        static let showToolTips = "blitz.menu.showToolTips"
        static let maxToolTip = "blitz.menu.maxToolTip"
        static let showImages = "blitz.menu.showImages"
        static let thumbW = "blitz.menu.thumbWidth"
        static let thumbH = "blitz.menu.thumbHeight"
        static let showIcons = "blitz.menu.showIcons"
        static let snippetsAbove = "blitz.menu.snippetsAbove"
        static let showClearInMenu = "blitz.menu.showClear"
        static let numericKeys = "blitz.menu.numericKeys"
        static let pasteAuto = "blitz.clipboard.pasteAutomatically"
        static let showStatusItem = "blitz.menu.showStatusItem"
        static let historyPopupCode = "blitz.hotkey.historyPopup.code"
        static let historyPopupMods = "blitz.hotkey.historyPopup.mods"
        static let settingsHotKeyCode = "blitz.hotkey.settings.code"
        static let settingsHotKeyMods = "blitz.hotkey.settings.mods"
        static let clearHistCode = "blitz.hotkey.clearHistory.code"
        static let clearHistMods = "blitz.hotkey.clearHistory.mods"
        static let editSnippetsCode = "blitz.hotkey.editSnippets.code"
        static let editSnippetsMods = "blitz.hotkey.editSnippets.mods"
        static let mainMenuCode = "blitz.hotkey.mainMenu.code"
        static let mainMenuMods = "blitz.hotkey.mainMenu.mods"
        static let iCloudSync = "blitz.sync.icloudEnabled"
        static let iCloudClipboard = "blitz.sync.icloudClipboardText"
    }

    var iCloudSyncEnabled: Bool {
        get { defaults.bool(forKey: Key.iCloudSync) }
        set { defaults.set(newValue, forKey: Key.iCloudSync) }
    }

    /// Sync plain-text clip index (not full image media) to iCloud Drive.
    var iCloudSyncClipboardText: Bool {
        get { defaults.bool(forKey: Key.iCloudClipboard) }
        set { defaults.set(newValue, forKey: Key.iCloudClipboard) }
    }

    var hotKeyCode: UInt32 {
        get {
            if defaults.object(forKey: Key.hotKeyCode) == nil { return UInt32(kVK_Space) }
            return UInt32(defaults.integer(forKey: Key.hotKeyCode))
        }
        set { defaults.set(Int(newValue), forKey: Key.hotKeyCode) }
    }

    var hotKeyModifiers: UInt32 {
        get {
            if defaults.object(forKey: Key.hotKeyModifiers) == nil {
                return UInt32(controlKey | optionKey)
            }
            return UInt32(defaults.integer(forKey: Key.hotKeyModifiers))
        }
        set { defaults.set(Int(newValue), forKey: Key.hotKeyModifiers) }
    }

    var clipboardMaxItems: Int {
        get {
            let v = defaults.integer(forKey: Key.clipboardMax)
            return v > 0 ? min(v, 1000) : 200
        }
        set { defaults.set(max(20, min(newValue, 1000)), forKey: Key.clipboardMax) }
    }

    var fileSearchLimit: Int {
        get {
            let v = defaults.integer(forKey: Key.fileSearchLimit)
            return v > 0 ? min(v, 100) : 35
        }
        set { defaults.set(max(10, min(newValue, 100)), forKey: Key.fileSearchLimit) }
    }

    var panelWidth: CGFloat {
        get {
            let v = defaults.double(forKey: Key.panelWidth)
            return v > 0 ? CGFloat(v) : 720
        }
        set { defaults.set(Double(max(480, min(newValue, 1200))), forKey: Key.panelWidth) }
    }

    var panelHeight: CGFloat {
        get {
            let v = defaults.double(forKey: Key.panelHeight)
            return v > 0 ? CGFloat(v) : 480
        }
        set { defaults.set(Double(max(320, min(newValue, 900))), forKey: Key.panelHeight) }
    }

    var didOpenSettingsOnce: Bool {
        get {
            return defaults.bool(forKey: Key.didOpenSettings)
        }
        set { defaults.set(newValue, forKey: Key.didOpenSettings) }
    }

    var showWelcomeOnLaunch: Bool {
        get {
            if defaults.object(forKey: Key.showWelcome) == nil { return true }
            return defaults.bool(forKey: Key.showWelcome)
        }
        set { defaults.set(newValue, forKey: Key.showWelcome) }
    }

    var clipboardHotKeyCode: UInt32 {
        get {
            if defaults.object(forKey: Key.clipboardHotKeyCode) == nil { return UInt32(kVK_ANSI_V) }
            return UInt32(defaults.integer(forKey: Key.clipboardHotKeyCode))
        }
        set { defaults.set(Int(newValue), forKey: Key.clipboardHotKeyCode) }
    }

    var clipboardHotKeyModifiers: UInt32 {
        get {
            if defaults.object(forKey: Key.clipboardHotKeyModifiers) == nil {
                return UInt32(controlKey | optionKey)
            }
            return UInt32(defaults.integer(forKey: Key.clipboardHotKeyModifiers))
        }
        set { defaults.set(Int(newValue), forKey: Key.clipboardHotKeyModifiers) }
    }

    /// Default ⇧⌘B for snippets menu (Clipy-compatible).
    var snippetsHotKeyCode: UInt32 {
        get {
            if defaults.object(forKey: Key.snippetsHotKeyCode) == nil { return UInt32(kVK_ANSI_B) }
            return UInt32(defaults.integer(forKey: Key.snippetsHotKeyCode))
        }
        set { defaults.set(Int(newValue), forKey: Key.snippetsHotKeyCode) }
    }

    var snippetsHotKeyModifiers: UInt32 {
        get {
            if defaults.object(forKey: Key.snippetsHotKeyModifiers) == nil {
                return UInt32(shiftKey | cmdKey)
            }
            return UInt32(defaults.integer(forKey: Key.snippetsHotKeyModifiers))
        }
        set { defaults.set(Int(newValue), forKey: Key.snippetsHotKeyModifiers) }
    }

    var pasteboardTypes: PasteboardTypeSettings {
        get {
            guard let data = defaults.data(forKey: Key.pasteboardTypes),
                  let decoded = try? JSONDecoder().decode(PasteboardTypeSettings.self, from: data) else {
                return .default
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.pasteboardTypes)
            }
        }
    }

    var excludedBundleIDs: [String] {
        get {
            return defaults.stringArray(forKey: Key.excludedApps) ?? []
        }
        set { defaults.set(newValue, forKey: Key.excludedApps) }
    }

    var ignoreConcealed: Bool {
        get {
            if defaults.object(forKey: Key.ignoreConcealed) == nil { return true }
            return defaults.bool(forKey: Key.ignoreConcealed)
        }
        set { defaults.set(newValue, forKey: Key.ignoreConcealed) }
    }

    var ignoreUniversalClipboard: Bool {
        get {
            return defaults.bool(forKey: Key.ignoreUniversal)
        }
        set { defaults.set(newValue, forKey: Key.ignoreUniversal) }
    }

    var overwriteSameHistory: Bool {
        get {
            if defaults.object(forKey: Key.overwriteSame) == nil { return true }
            return defaults.bool(forKey: Key.overwriteSame)
        }
        set { defaults.set(newValue, forKey: Key.overwriteSame) }
    }

    /// When true, allow duplicate content as separate entries.
    var copySameHistory: Bool {
        get {
            return defaults.bool(forKey: Key.copySame)
        }
        set { defaults.set(newValue, forKey: Key.copySame) }
    }

    var reorderAfterPaste: Bool {
        get {
            if defaults.object(forKey: Key.reorderAfterPaste) == nil { return true }
            return defaults.bool(forKey: Key.reorderAfterPaste)
        }
        set { defaults.set(newValue, forKey: Key.reorderAfterPaste) }
    }

    var clearHistoryOnQuit: Bool {
        get {
            return defaults.bool(forKey: Key.clearOnQuit)
        }
        set { defaults.set(newValue, forKey: Key.clearOnQuit) }
    }

    var clearHistoryPeriodically: Bool {
        get {
            return defaults.bool(forKey: Key.clearPeriodically)
        }
        set { defaults.set(newValue, forKey: Key.clearPeriodically) }
    }

    var historyClearInterval: HistoryClearInterval {
        get {
            let v = defaults.integer(forKey: Key.clearInterval)
            return HistoryClearInterval(rawValue: v) ?? .day
        }
        set { defaults.set(newValue.rawValue, forKey: Key.clearInterval) }
    }

    var showAlertBeforeClearHistory: Bool {
        get {
            if defaults.object(forKey: Key.alertBeforeClear) == nil { return true }
            return defaults.bool(forKey: Key.alertBeforeClear)
        }
        set { defaults.set(newValue, forKey: Key.alertBeforeClear) }
    }

    var observeScreenshots: Bool {
        get {
            return defaults.bool(forKey: Key.observeScreenshots)
        }
        set { defaults.set(newValue, forKey: Key.observeScreenshots) }
    }

    var showColorPreviewInMenu: Bool {
        get {
            if defaults.object(forKey: Key.showColorPreview) == nil { return true }
            return defaults.bool(forKey: Key.showColorPreview)
        }
        set { defaults.set(newValue, forKey: Key.showColorPreview) }
    }

    var menuHistoryCount: Int {
        get {
            let v = defaults.integer(forKey: Key.menuHistoryCount)
            return v > 0 ? min(v, 50) : 20
        }
        set { defaults.set(max(5, min(newValue, 50)), forKey: Key.menuHistoryCount) }
    }

    var showNumbersInMenu: Bool {
        get {
            if defaults.object(forKey: Key.showNumbersInMenu) == nil { return true }
            return defaults.bool(forKey: Key.showNumbersInMenu)
        }
        set { defaults.set(newValue, forKey: Key.showNumbersInMenu) }
    }

    var pastePlainTextEnabled: Bool {
        get {
            if defaults.object(forKey: Key.pastePlainMod) == nil { return true }
            return defaults.bool(forKey: Key.pastePlainMod)
        }
        set { defaults.set(newValue, forKey: Key.pastePlainMod) }
    }

    var pastePlainTextModifier: ModifierActionKey {
        get {
            return ModifierActionKey(rawValue: defaults.integer(forKey: Key.pastePlainKey)) ?? .command
        }
        set { defaults.set(newValue.rawValue, forKey: Key.pastePlainKey) }
    }

    var deleteHistoryEnabled: Bool {
        get {
            if defaults.object(forKey: Key.deleteHistMod) == nil { return true }
            return defaults.bool(forKey: Key.deleteHistMod)
        }
        set { defaults.set(newValue, forKey: Key.deleteHistMod) }
    }

    var deleteHistoryModifier: ModifierActionKey {
        get {
            return ModifierActionKey(rawValue: defaults.integer(forKey: Key.deleteHistKey)) ?? .option
        }
        set { defaults.set(newValue.rawValue, forKey: Key.deleteHistKey) }
    }

    var pasteAndDeleteEnabled: Bool {
        get {
            if defaults.object(forKey: Key.pasteDeleteMod) == nil { return true }
            return defaults.bool(forKey: Key.pasteDeleteMod)
        }
        set { defaults.set(newValue, forKey: Key.pasteDeleteMod) }
    }

    var pasteAndDeleteModifier: ModifierActionKey {
        get {
            return ModifierActionKey(rawValue: defaults.integer(forKey: Key.pasteDeleteKey)) ?? .shift
        }
        set { defaults.set(newValue.rawValue, forKey: Key.pasteDeleteKey) }
    }

    /// Items shown at top level before folding into submenus (0 = all in folders).
    var inlineMenuItemLimit: Int {
        get {
            if defaults.object(forKey: Key.inlineMenuLimit) == nil { return 10 }
            return max(0, min(defaults.integer(forKey: Key.inlineMenuLimit), 100))
        }
        set { defaults.set(max(0, min(newValue, 100)), forKey: Key.inlineMenuLimit) }
    }

    var folderMenuItemLimit: Int {
        get {
            let v = defaults.integer(forKey: Key.folderMenuLimit)
            return v > 0 ? min(v, 100) : 20
        }
        set { defaults.set(max(1, min(newValue, 100)), forKey: Key.folderMenuLimit) }
    }

    var maxMenuTitleLength: Int {
        get {
            let v = defaults.integer(forKey: Key.maxMenuTitle)
            return v > 0 ? min(v, 1000) : 60
        }
        set { defaults.set(max(8, min(newValue, 1000)), forKey: Key.maxMenuTitle) }
    }

    var startsMenuAtZero: Bool {
        get {
            return defaults.bool(forKey: Key.startsAtZero)
        }
        set { defaults.set(newValue, forKey: Key.startsAtZero) }
    }

    var showToolTipsInMenu: Bool {
        get {
            if defaults.object(forKey: Key.showToolTips) == nil { return true }
            return defaults.bool(forKey: Key.showToolTips)
        }
        set { defaults.set(newValue, forKey: Key.showToolTips) }
    }

    var maxToolTipLength: Int {
        get {
            let v = defaults.integer(forKey: Key.maxToolTip)
            return v > 0 ? min(v, 10_000) : 400
        }
        set { defaults.set(max(40, min(newValue, 10_000)), forKey: Key.maxToolTip) }
    }

    var showImagesInMenu: Bool {
        get {
            if defaults.object(forKey: Key.showImages) == nil { return true }
            return defaults.bool(forKey: Key.showImages)
        }
        set { defaults.set(newValue, forKey: Key.showImages) }
    }

    var thumbnailWidth: CGFloat {
        get {
            let v = defaults.double(forKey: Key.thumbW)
            return v > 0 ? CGFloat(min(v, 512)) : 32
        }
        set { defaults.set(Double(max(8, min(newValue, 512))), forKey: Key.thumbW) }
    }

    var thumbnailHeight: CGFloat {
        get {
            let v = defaults.double(forKey: Key.thumbH)
            return v > 0 ? CGFloat(min(v, 512)) : 32
        }
        set { defaults.set(Double(max(8, min(newValue, 512))), forKey: Key.thumbH) }
    }

    var showIconsInMenu: Bool {
        get {
            if defaults.object(forKey: Key.showIcons) == nil { return true }
            return defaults.bool(forKey: Key.showIcons)
        }
        set { defaults.set(newValue, forKey: Key.showIcons) }
    }

    var showsSnippetsAboveHistory: Bool {
        get {
            return defaults.bool(forKey: Key.snippetsAbove)
        }
        set { defaults.set(newValue, forKey: Key.snippetsAbove) }
    }

    var showsClearHistoryMenuItem: Bool {
        get {
            if defaults.object(forKey: Key.showClearInMenu) == nil { return true }
            return defaults.bool(forKey: Key.showClearInMenu)
        }
        set { defaults.set(newValue, forKey: Key.showClearInMenu) }
    }

    var addsNumericKeyEquivalents: Bool {
        get {
            if defaults.object(forKey: Key.numericKeys) == nil { return true }
            return defaults.bool(forKey: Key.numericKeys)
        }
        set { defaults.set(newValue, forKey: Key.numericKeys) }
    }

    /// When false, selecting a history item only copies to the pasteboard.
    var pasteAutomatically: Bool {
        get {
            if defaults.object(forKey: Key.pasteAuto) == nil { return true }
            return defaults.bool(forKey: Key.pasteAuto)
        }
        set { defaults.set(newValue, forKey: Key.pasteAuto) }
    }

    var showStatusItem: Bool {
        get {
            if defaults.object(forKey: Key.showStatusItem) == nil { return true }
            return defaults.bool(forKey: Key.showStatusItem)
        }
        set { defaults.set(newValue, forKey: Key.showStatusItem) }
    }

    /// Pop history menu at mouse — default ⌃⌘V (Clipy History).
    var historyPopupHotKeyCode: UInt32 {
        get {
            if defaults.object(forKey: Key.historyPopupCode) == nil { return UInt32(kVK_ANSI_V) }
            return UInt32(defaults.integer(forKey: Key.historyPopupCode))
        }
        set { defaults.set(Int(newValue), forKey: Key.historyPopupCode) }
    }

    var historyPopupHotKeyModifiers: UInt32 {
        get {
            if defaults.object(forKey: Key.historyPopupMods) == nil {
                return UInt32(controlKey | cmdKey)
            }
            return UInt32(defaults.integer(forKey: Key.historyPopupMods))
        }
        set { defaults.set(Int(newValue), forKey: Key.historyPopupMods) }
    }

    /// Settings — default ⌃⌥⇧⌘V (Clipy).
    var settingsHotKeyCode: UInt32 {
        get {
            if defaults.object(forKey: Key.settingsHotKeyCode) == nil { return UInt32(kVK_ANSI_V) }
            return UInt32(defaults.integer(forKey: Key.settingsHotKeyCode))
        }
        set { defaults.set(Int(newValue), forKey: Key.settingsHotKeyCode) }
    }

    var settingsHotKeyModifiers: UInt32 {
        get {
            if defaults.object(forKey: Key.settingsHotKeyMods) == nil {
                return UInt32(controlKey | optionKey | shiftKey | cmdKey)
            }
            return UInt32(defaults.integer(forKey: Key.settingsHotKeyMods))
        }
        set { defaults.set(Int(newValue), forKey: Key.settingsHotKeyMods) }
    }

    var clearHistoryHotKeyCode: UInt32 {
        get {
            return UInt32(defaults.integer(forKey: Key.clearHistCode))
        }
        set { defaults.set(Int(newValue), forKey: Key.clearHistCode) }
    }

    var clearHistoryHotKeyModifiers: UInt32 {
        get {
            return UInt32(defaults.integer(forKey: Key.clearHistMods))
        }
        set { defaults.set(Int(newValue), forKey: Key.clearHistMods) }
    }

    var editSnippetsHotKeyCode: UInt32 {
        get {
            return UInt32(defaults.integer(forKey: Key.editSnippetsCode))
        }
        set { defaults.set(Int(newValue), forKey: Key.editSnippetsCode) }
    }

    var editSnippetsHotKeyModifiers: UInt32 {
        get {
            return UInt32(defaults.integer(forKey: Key.editSnippetsMods))
        }
        set { defaults.set(Int(newValue), forKey: Key.editSnippetsMods) }
    }

    /// Main combined menu at mouse — default ⌥⌘V (avoids clashing with common ⇧⌘V clipboard binds).
    var mainMenuHotKeyCode: UInt32 {
        get {
            if defaults.object(forKey: Key.mainMenuCode) == nil { return UInt32(kVK_ANSI_V) }
            return UInt32(defaults.integer(forKey: Key.mainMenuCode))
        }
        set { defaults.set(Int(newValue), forKey: Key.mainMenuCode) }
    }

    var mainMenuHotKeyModifiers: UInt32 {
        get {
            if defaults.object(forKey: Key.mainMenuMods) == nil {
                return UInt32(optionKey | cmdKey)
            }
            return UInt32(defaults.integer(forKey: Key.mainMenuMods))
        }
        set { defaults.set(Int(newValue), forKey: Key.mainMenuMods) }
    }

    var hotKeyDisplayString: String {
        HotKeyCodec.displayString(keyCode: hotKeyCode, modifiers: hotKeyModifiers)
    }

    var clipboardHotKeyDisplayString: String {
        HotKeyCodec.displayString(keyCode: clipboardHotKeyCode, modifiers: clipboardHotKeyModifiers)
    }

    var snippetsHotKeyDisplayString: String {
        HotKeyCodec.displayString(keyCode: snippetsHotKeyCode, modifiers: snippetsHotKeyModifiers)
    }

    var historyPopupHotKeyDisplayString: String {
        HotKeyCodec.displayString(keyCode: historyPopupHotKeyCode, modifiers: historyPopupHotKeyModifiers)
    }

    var mainMenuHotKeyDisplayString: String {
        HotKeyCodec.displayString(keyCode: mainMenuHotKeyCode, modifiers: mainMenuHotKeyModifiers)
    }

    var settingsHotKeyDisplayString: String {
        HotKeyCodec.displayString(keyCode: settingsHotKeyCode, modifiers: settingsHotKeyModifiers)
    }

    func resetHotKeyToDefault() {
        hotKeyCode = UInt32(kVK_Space)
        hotKeyModifiers = UInt32(controlKey | optionKey)
    }

    func resetClipboardHotKeyToDefault() {
        clipboardHotKeyCode = UInt32(kVK_ANSI_V)
        clipboardHotKeyModifiers = UInt32(controlKey | optionKey)
    }

    func resetMainMenuHotKeyToDefault() {
        mainMenuHotKeyCode = UInt32(kVK_ANSI_V)
        mainMenuHotKeyModifiers = UInt32(optionKey | cmdKey)
    }

    func resetSnippetsHotKeyToDefault() {
        snippetsHotKeyCode = UInt32(kVK_ANSI_B)
        snippetsHotKeyModifiers = UInt32(shiftKey | cmdKey)
    }
}

enum HotKeyCodec {
    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName(keyCode))
        return parts.joined()
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    static func keyName(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Esc"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Fwd Del"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        default: return "Key\(keyCode)"
        }
    }
}
