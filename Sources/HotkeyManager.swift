import Foundation
import Carbon
import AppKit
import ApplicationServices

// Словарь для преобразования строковых названий клавиш в их виртуальные коды
private let keyNameToKeyCode: [String: CGKeyCode] = [
    "A": CGKeyCode(kVK_ANSI_A), "B": CGKeyCode(kVK_ANSI_B), "C": CGKeyCode(kVK_ANSI_C),
    "D": CGKeyCode(kVK_ANSI_D), "E": CGKeyCode(kVK_ANSI_E), "F": CGKeyCode(kVK_ANSI_F),
    "G": CGKeyCode(kVK_ANSI_G), "H": CGKeyCode(kVK_ANSI_H), "I": CGKeyCode(kVK_ANSI_I),
    "J": CGKeyCode(kVK_ANSI_J), "K": CGKeyCode(kVK_ANSI_K), "L": CGKeyCode(kVK_ANSI_L),
    "M": CGKeyCode(kVK_ANSI_M), "N": CGKeyCode(kVK_ANSI_N), "O": CGKeyCode(kVK_ANSI_O),
    "P": CGKeyCode(kVK_ANSI_P), "Q": CGKeyCode(kVK_ANSI_Q), "R": CGKeyCode(kVK_ANSI_R),
    "S": CGKeyCode(kVK_ANSI_S), "T": CGKeyCode(kVK_ANSI_T), "U": CGKeyCode(kVK_ANSI_U),
    "V": CGKeyCode(kVK_ANSI_V), "W": CGKeyCode(kVK_ANSI_W), "X": CGKeyCode(kVK_ANSI_X),
    "Y": CGKeyCode(kVK_ANSI_Y), "Z": CGKeyCode(kVK_ANSI_Z)
]

struct Hotkey {
    let flags: CGEventFlags
    let keyCode: CGKeyCode
    let action: () -> Void
}

public final class HotkeyManager {
    fileprivate enum Constants {
        static let debounceInterval: TimeInterval = 0.5
        static let clipboardDelay: TimeInterval = 0.1
        static let pasteDelay: TimeInterval = 0.05
    }
    
    private var hotkeys: [Hotkey] = []
    private let layoutSwitchAction = LayoutSwitchAction()
    private let tokenTracker = TokenTracker()
    private let autoReplacer = AutoReplacer()
    private let replacementExecutor = ReplacementExecutor()
    private var isOptionKeyRegistered = false
    private var eventTap: CFMachPort?
    private var isProcessing = false
    private var optionIsolatedCandidate = false

    public init() {
        // Настройка связей между компонентами автозамены
        autoReplacer.setExecutor(replacementExecutor)
        replacementExecutor.setSuspendResumeCallbacks(
            suspend: { [weak self] in self?.suspendEventTap() },
            resume: { [weak self] in self?.resumeEventTap() }
        )
    }

    func register(prompts: [Prompt]) {
        let promptHotkeys = prompts.compactMap { prompt -> Hotkey? in
            guard let (flags, keyCode) = parseHotkey(prompt.config.hotkey) else {
                Log.d("HotkeyManager", "Invalid hotkey: \(prompt.config.hotkey)")
                return nil
            }
            return Hotkey(flags: flags, keyCode: keyCode) { /* AI action placeholder */ }
        }
        self.hotkeys.append(contentsOf: promptHotkeys)
        setupEventTap()
    }
    
    public func registerCaseTransform(hotkeyString: String) {
        guard let (flags, keyCode) = parseHotkey(hotkeyString) else {
            Log.d("HotkeyManager", "Invalid case transform hotkey: \(hotkeyString)")
            return
        }
        let hotkey = Hotkey(flags: flags, keyCode: keyCode) { /* Case transform placeholder */ }
        self.hotkeys.append(hotkey)
    }
    
    public func registerLayoutSwitch() {
        isOptionKeyRegistered = true
        Log.d("HotkeyManager", "✅ Option key registered")
        setupEventTap()
    }
    
    private func suspendEventTap() {
        guard let eventTap = eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        Log.d("HotkeyManager", "EventTap suspended")
    }
    
    private func resumeEventTap() {
        guard let eventTap = eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        Log.d("HotkeyManager", "EventTap resumed")
    }
    
    private func parseHotkey(_ hotkeyString: String) -> (CGEventFlags, CGKeyCode)? {
        let parts = hotkeyString.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }

        var flags: CGEventFlags = []
        var key: String?

        for part in parts {
            switch part.lowercased() {
            case "control": flags.insert(.maskControl)
            case "option": flags.insert(.maskAlternate)
            case "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            default: key = part.uppercased()
            }
        }
        
        guard let keyStr = key, let keyCode = keyNameToKeyCode[keyStr] else { return nil }
        return (flags, keyCode)
    }
    
    private func setupEventTap() {
        guard !hotkeys.isEmpty || isOptionKeyRegistered else {
            Log.d("HotkeyManager", "No hotkeys to register")
            return
        }
        
        var eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        if isOptionKeyRegistered {
            eventMask |= (1 << CGEventType.flagsChanged.rawValue)
        }
        
        guard let newEventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            Log.d("HotkeyManager", "Failed to create event tap")
            return
        }
        
        self.eventTap = newEventTap
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newEventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newEventTap, enable: true)
        
        Log.d("HotkeyManager", "EventTap enabled: \(hotkeys.count) hotkeys, Option: \(isOptionKeyRegistered)")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown: return handleKeyDown(event) ? nil : Unmanaged.passUnretained(event)
        case .keyUp: return handleKeyUp(event) ? nil : Unmanaged.passUnretained(event)  
        case .flagsChanged: return handleFlagsChanged(event) ? nil : Unmanaged.passUnretained(event)
        default: return Unmanaged.passUnretained(event)
        }
    }
    
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        // Realtime tokenization
        tokenTracker.handleKeyDown(event, isProcessing: isProcessing)
        
        // Auto-replacement analysis
        handleKeyDownForAutoReplacement(event)
        
        // Hotkey processing
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        for hotkey in hotkeys {
            if keyCode == hotkey.keyCode && flags.contains(hotkey.flags) {
                Log.d("HotkeyManager", "Hotkey activated")
                hotkey.action()
                return true // Consume event
            }
        }
        
        return false // Pass through
    }
    
    private func handleKeyUp(_ event: CGEvent) -> Bool {
        handleKeyUpForAutoReplacement(event)
        return false // Never consume keyUp events
    }
    
    private func handleFlagsChanged(_ event: CGEvent) -> Bool {
        guard isOptionKeyRegistered else { return false }
        
        let flags = event.flags
        let previousFlags = CGEventSource.flagsState(.hidSystemState)
        let optionPressed = flags.contains(.maskAlternate)
        let optionWasPressed = previousFlags.contains(.maskAlternate)
        
        // Only handle isolated Option key (no other modifiers)
        let otherModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskSecondaryFn, .maskHelp]
        let hasOtherModifiers = !otherModifiers.intersection(flags).isEmpty
        
        if optionPressed && !optionWasPressed && !hasOtherModifiers {
            Log.d("HotkeyManager", "Isolated Option pressed - candidate")
            optionIsolatedCandidate = true
        }
        
        if optionPressed && hasOtherModifiers && optionIsolatedCandidate {
            Log.d("HotkeyManager", "Option with modifiers - cancelling")
            optionIsolatedCandidate = false
        }
        
        if !optionPressed && optionWasPressed && optionIsolatedCandidate && !isProcessing {
            Log.d("HotkeyManager", "Isolated Option released - layout switch")
            optionIsolatedCandidate = false
            isProcessing = true
            
            DispatchQueue.main.async { [weak self] in
                self?.performLayoutSwitchAsync()
            }
            return true // Consume isolated Option release
        }
        
        if hasOtherModifiers {
            Log.d("HotkeyManager", "Option with modifiers - passing through")
        }
        
        return false
    }
    
    private func performLayoutSwitchAsync() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.performLayoutSwitchAsync() }
            return
        }
        
        Log.d("HotkeyManager", "Starting layout switch")
        suspendEventTap()
        
        layoutSwitchAction.performHotkeyAsync(
            suspendCallback: { [weak self] in self?.suspendEventTap() },
            resumeCallback: { [weak self] in 
                self?.resumeEventTap()
                self?.isProcessing = false
                self?.optionIsolatedCandidate = false
            }
        )
    }
    
    // MARK: - Auto-Replacement Support
    
    private func shouldProcessAutoReplacement() -> Bool {
        // Context validation теперь обрабатывается в TokenTracker с grace period logic
        return !isProcessing && !tokenTracker.isPostReplacementMode()
    }
    
    private func handleKeyDownForAutoReplacement(_ event: CGEvent) {
        let currentToken = tokenTracker.getCurrentToken()
        guard currentToken.count >= 3 else { return }
        guard shouldProcessAutoReplacement() else {
            if tokenTracker.isPostReplacementMode() {
                Log.d("HotkeyManager", "⏸️ ANALYSIS SKIPPED: post-replacement active")
            }
            return
        }
        
        autoReplacer.analyzeTokenForPlanning(currentToken)
    }
    
    private func handleKeyUpForAutoReplacement(_ event: CGEvent) {
        guard shouldProcessAutoReplacement() else { return }
        
        autoReplacer.executePlannedReplacement { [weak self] success, originalToken, replacementText in
            if success {
                self?.tokenTracker.updateTokenAfterReplacement(newText: replacementText, originalToken: originalToken)
            }
        }
    }
}

// MARK: - Layout Switch Action

final class LayoutSwitchAction {
    private let clipboardProcessor = ClipboardProcessor()
    private var lastActivationTime: Date = Date.distantPast
    
    private func getFocusedElementRole() -> String? {
        let systemElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focused = focusedElement else { return nil }
        
        let focusedAXElement = focused as! AXUIElement
        var roleValue: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(focusedAXElement, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String else { return nil }
        
        return role
    }
    
    private func isValidTextRole(_ role: String) -> Bool {
        let textRoles = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXSecureTextField", "AXStaticText"]
        if textRoles.contains(role) { return true }
        
        // AXGroup in browsers can be rich text editors
        if role == "AXGroup" && ApplicationDetector.isBrowser() {
            Log.d("LayoutSwitchAction", "AXGroup in browser - likely text editor")
            return true
        }
        
        return false
    }
    
    private func hasTextSelection(_ element: AXUIElement) -> Bool {
        var selectedText: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText) == .success,
              let text = selectedText as? String,
              !text.isEmpty else { return false }
        
        Log.d("LayoutSwitchAction", "Text selection: '\(text.prefix(50))...'")
        return true
    }
    
    private func checkValidTextContext() -> Bool {
        guard !ApplicationDetector.isBlocked() else { return false }
        
        guard let role = getFocusedElementRole() else {
            Log.d("LayoutSwitchAction", "No focused element - allowing")
            return true
        }
        
        Log.d("LayoutSwitchAction", "Element: '\(role)' in \(ApplicationDetector.currentBundleID())")
        
        if isValidTextRole(role) {
            let systemElement = AXUIElementCreateSystemWide()
            var focusedElement: CFTypeRef?
            
            if AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
               let focused = focusedElement {
                let focusedAXElement = focused as! AXUIElement
                
                if hasTextSelection(focusedAXElement) {
                    return true
                } else {
                    // Check for Canva web app
                    let canvaDetection = UniversalCanvaDetector.detect()
                    if canvaDetection.detected && ApplicationDetector.isBrowser() {
                        Log.d("LayoutSwitchAction", "Canva detected without AX selection")
                        return false
                    } else {
                        Log.d("LayoutSwitchAction", "Text element without selection - clipboard fallback")
                        return true
                    }
                }
            }
            return true
        } else {
            Log.d("LayoutSwitchAction", "Non-text element - likely Canvas")
            return false
        }
    }
    
    func performHotkeyAsync(suspendCallback: @escaping () -> Void, resumeCallback: @escaping () -> Void) {
        Log.d("LayoutSwitchAction", "Starting layout switch")
        
        // Debouncing
        let currentTime = Date()
        if currentTime.timeIntervalSince(lastActivationTime) < HotkeyManager.Constants.debounceInterval {
            Log.d("LayoutSwitchAction", "Debounced - too soon")
            resumeCallback()
            return
        }
        lastActivationTime = currentTime
        
        // Context validation
        guard checkValidTextContext() else {
            Log.d("LayoutSwitchAction", "Invalid context - cancelling")
            resumeCallback()
            return
        }
        
        // Backup pasteboard
        let pasteboardBackup = PasteboardManager.backupPasteboard()
        let previousClipboardText = NSPasteboard.general.string(forType: .string) ?? ""
        
        // Copy selection
        guard clipboardProcessor.copySelection() else {
            Log.d("LayoutSwitchAction", "Copy failed")
            resumeCallback()
            SoundPlayer.shared.playError()
            return
        }
        
        // Process after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + HotkeyManager.Constants.clipboardDelay) { [weak self] in
            self?.clipboardProcessor.processClipboardContent(
                pasteboardBackup: pasteboardBackup,
                previousClipboardText: previousClipboardText
            ) { result in
                self?.handleProcessingResult(result, pasteboardBackup: pasteboardBackup, resumeCallback: resumeCallback)
            }
        }
    }
    
    private func handleProcessingResult(_ result: ClipboardProcessor.ProcessingResult, pasteboardBackup: PasteboardManager.PasteboardBackup, resumeCallback: @escaping () -> Void) {
        guard result.success else {
            Log.d("LayoutSwitchAction", "Processing failed: \(result.reason)")
            PasteboardManager.restorePasteboard(pasteboardBackup)
            resumeCallback()
            
            if !result.reason.contains("No selection detected") {
                SoundPlayer.shared.playError()
            }
            return
        }
        
        // Paste converted text
        guard clipboardProcessor.pasteContent() else {
            Log.d("LayoutSwitchAction", "Paste failed")
            PasteboardManager.restorePasteboard(pasteboardBackup)
            resumeCallback()
            SoundPlayer.shared.playError()
            return
        }
        
        // Complete after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + HotkeyManager.Constants.pasteDelay) {
            if let originalText = result.originalText, let convertedText = result.convertedText {
                InputSourceManager.switchBasedOnConvertedText(originalText: originalText, convertedText: convertedText)
            }
            
            PasteboardManager.restorePasteboard(pasteboardBackup)
            resumeCallback()
            SoundPlayer.shared.playSuccess()
            Log.d("LayoutSwitchAction", "Layout switch completed")
        }
    }
    
    // Legacy method for backward compatibility
    func performHotkey() {
        performHotkeyAsync(suspendCallback: {}, resumeCallback: {})
    }
}

// MARK: - PasteboardManager

final class PasteboardManager {
    struct PasteboardItemData {
        let types: [NSPasteboard.PasteboardType]
        let data: [NSPasteboard.PasteboardType: Data]
    }
    
    struct PasteboardBackup {
        let itemsData: [PasteboardItemData]
        let fallbackString: String?
    }
    
    static func backupPasteboard() -> PasteboardBackup {
        let pasteboard = NSPasteboard.general
        let items = pasteboard.pasteboardItems ?? []
        let fallbackString = pasteboard.string(forType: .string)
        
        var itemsData: [PasteboardItemData] = []
        
        for item in items {
            let types = item.types
            var dataDict: [NSPasteboard.PasteboardType: Data] = [:]
            
            for type in types {
                if let data = item.data(forType: type) {
                    dataDict[type] = data
                }
            }
            
            itemsData.append(PasteboardItemData(types: types, data: dataDict))
        }
        
        Log.d("PasteboardManager", "Backed up \(itemsData.count) items")
        return PasteboardBackup(itemsData: itemsData, fallbackString: fallbackString)
    }
    
    static func restorePasteboard(_ backup: PasteboardBackup) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if !backup.itemsData.isEmpty {
            var newItems: [NSPasteboardItem] = []
            
            for itemData in backup.itemsData {
                let newItem = NSPasteboardItem()
                for (type, data) in itemData.data {
                    newItem.setData(data, forType: type)
                }
                newItems.append(newItem)
            }
            
            if !newItems.isEmpty {
                pasteboard.writeObjects(newItems)
                Log.d("PasteboardManager", "Restored \(newItems.count) items")
            } else if let fallbackString = backup.fallbackString {
                pasteboard.setString(fallbackString, forType: .string)
                Log.d("PasteboardManager", "Restored fallback string")
            }
        } else if let fallbackString = backup.fallbackString {
            pasteboard.setString(fallbackString, forType: .string)
            Log.d("PasteboardManager", "Restored fallback")
        }
    }
}

// Placeholder types for compatibility (minimal implementation)
struct Prompt { let config: PromptConfig }
struct PromptConfig { let hotkey: String }