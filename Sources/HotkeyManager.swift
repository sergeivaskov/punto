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
    private var hotkeys: [Hotkey] = []
    private let aiAction = AITransformAction()
    private let caseAction = CaseTransformAction()
    private let layoutSwitchAction = LayoutSwitchAction()
    private var isOptionKeyRegistered = false
    private var eventTap: CFMachPort?
    private var isProcessing = false

    public init() {}

    func register(prompts: [Prompt]) {
        let promptHotkeys = prompts.compactMap { prompt -> Hotkey? in
            guard let (flags, keyCode) = parseHotkey(prompt.config.hotkey) else {
                Log.d("HotkeyManager", "Invalid hotkey string: \(prompt.config.hotkey)")
                return nil
            }
            return Hotkey(flags: flags, keyCode: keyCode) { [weak self] in
                self?.aiAction.perform(for: prompt)
            }
        }
        self.hotkeys.append(contentsOf: promptHotkeys)
        setupEventTap()
    }
    
    public func registerCaseTransform(hotkeyString: String) {
        guard let (flags, keyCode) = parseHotkey(hotkeyString) else {
            Log.d("HotkeyManager", "Invalid hotkey string for case transform: \(hotkeyString)")
            return
        }
        let hotkey = Hotkey(flags: flags, keyCode: keyCode) { [weak self] in
            self?.caseAction.performHotkey()
        }
        self.hotkeys.append(hotkey)
    }
    
    public func registerLayoutSwitch() {
        isOptionKeyRegistered = true
        Log.d("HotkeyManager", "Registered Option key for layout switching")
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
            Log.d("HotkeyManager", "No valid hotkeys to register.")
            return
        }
        
        var eventMask = (1 << CGEventType.keyDown.rawValue)
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
            Log.d("HotkeyManager", "Failed to create event tap.")
            return
        }
        
        self.eventTap = newEventTap
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newEventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newEventTap, enable: true)
        
        Log.d("HotkeyManager", "Event tap enabled for \(hotkeys.count) hotkeys and Option key: \(isOptionKeyRegistered).")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle regular hotkeys
        if type == .keyDown {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            
            for hotkey in hotkeys {
                // Сравниваем только релевантные флаги, игнорируя, например, caps lock
                if keyCode == hotkey.keyCode && flags.contains(hotkey.flags) {
                    Log.d("HotkeyManager", "Hotkey activated")
                    hotkey.action()
                    return nil // Гасим событие
                }
            }
        }
        
        // Handle Option key for layout switching
        if type == .flagsChanged && isOptionKeyRegistered {
            let flags = event.flags
            let previousFlags = CGEventSource.flagsState(.hidSystemState)
            
            // Check if Option key was just pressed (not released)
            let optionPressed = flags.contains(.maskAlternate)
            let optionWasPressed = previousFlags.contains(.maskAlternate)
            
            if optionPressed && !optionWasPressed && !isProcessing {
                // Option key was just pressed - trigger layout switch asynchronously
                Log.d("HotkeyManager", "Option key pressed - triggering layout switch")
                isProcessing = true
                
                DispatchQueue.main.async { [weak self] in
                    self?.performLayoutSwitchAsync()
                }
                return nil // Consume the event
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func performLayoutSwitchAsync() {
        // Ensure we're on main queue
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.performLayoutSwitchAsync()
            }
            return
        }
        
        Log.d("HotkeyManager", "Starting async layout switch")
        
        // Suspend EventTap to prevent self-capture
        suspendEventTap()
        
        // Pass suspend/resume methods to the action
        layoutSwitchAction.performHotkeyAsync(
            suspendCallback: { [weak self] in self?.suspendEventTap() },
            resumeCallback: { [weak self] in 
                self?.resumeEventTap()
                self?.isProcessing = false
            }
        )
    }
}

// MARK: - Action Classes

final class LayoutSwitchAction {
    private let layoutConverter = QwertyJcukenLayoutConverter()
    
    private func checkAXSelectedText() -> Bool {
        // Create system-wide accessibility object
        let systemElement = AXUIElementCreateSystemWide()
        
        // Get the focused UI element
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard focusResult == .success, let focused = focusedElement else {
            Log.d("LayoutSwitchAction", "AX: No focused element found, fallback to clipboard check")
            return true // Fallback to old behavior if AX fails
        }
        
        // Get selected text from the focused element
        var selectedText: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        
        guard selectedResult == .success, 
              let text = selectedText as? String,
              !text.isEmpty else {
            Log.d("LayoutSwitchAction", "AX: No text selection detected")
            return false
        }
        
        Log.d("LayoutSwitchAction", "AX: Text selection detected: '\(text.prefix(50))...'")
        return true
    }
    
    func performHotkeyAsync(suspendCallback: @escaping () -> Void, resumeCallback: @escaping () -> Void) {
        Log.d("LayoutSwitchAction", "Starting async layout switch operation")
        
        // Context Gating: Check for real text selection using AX API
        guard checkAXSelectedText() else {
            Log.d("LayoutSwitchAction", "Context Gating: No real text selection detected, cancelling operation")
            resumeCallback()
            return
        }
        
        // Backup current pasteboard and save current string for comparison
        let pasteboardBackup = PasteboardManager.backupPasteboard()
        let previousClipboardText = NSPasteboard.general.string(forType: .string) ?? ""
        
        // Copy selection to clipboard (Cmd+C)
        guard simulateKeyCombination(.maskCommand, CGKeyCode(kVK_ANSI_C)) else {
            Log.d("LayoutSwitchAction", "Failed to copy selection")
            resumeCallback()
            SoundPlayer.shared.playError()
            return
        }
        
        // Wait for clipboard to be populated asynchronously
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.processClipboardContent(
                pasteboardBackup: pasteboardBackup,
                previousClipboardText: previousClipboardText,
                resumeCallback: resumeCallback
            )
        }
    }
    
    private func processClipboardContent(pasteboardBackup: PasteboardManager.PasteboardBackup, previousClipboardText: String, resumeCallback: @escaping () -> Void) {
        // Read and analyze text from clipboard
        guard let clipboardText = NSPasteboard.general.string(forType: .string),
              !clipboardText.isEmpty else {
            Log.d("LayoutSwitchAction", "No text in clipboard")
            PasteboardManager.restorePasteboard(pasteboardBackup)
            resumeCallback()
            SoundPlayer.shared.playError()
            return
        }
        
        // Context Gating: Check if clipboard actually changed (i.e., there was a selection)
        guard clipboardText != previousClipboardText else {
            Log.d("LayoutSwitchAction", "No selection detected - clipboard unchanged, cancelling operation")
            PasteboardManager.restorePasteboard(pasteboardBackup)
            resumeCallback()
            return
        }
        
        // Check if text contains letters (ignore pure symbols/numbers)
        guard clipboardText.contains(where: { $0.isLetter }) else {
            Log.d("LayoutSwitchAction", "Text contains no letters, skipping conversion")
            PasteboardManager.restorePasteboard(pasteboardBackup)
            resumeCallback()
            return
        }
        
        // Convert to opposite layout
        let convertedText = layoutConverter.convertToOppositeLayout(clipboardText)
        
        Log.d("LayoutSwitchAction", "Converting '\(clipboardText)' -> '\(convertedText)'")
        
        // Set converted text to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(convertedText, forType: .string)
        
        // Paste converted text (Cmd+V)
        guard simulateKeyCombination(.maskCommand, CGKeyCode(kVK_ANSI_V)) else {
            Log.d("LayoutSwitchAction", "Failed to paste converted text")
            PasteboardManager.restorePasteboard(pasteboardBackup)
            resumeCallback()
            SoundPlayer.shared.playError()
            return
        }
        
        // Wait for paste to complete asynchronously
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Restore original pasteboard
            PasteboardManager.restorePasteboard(pasteboardBackup)
            
            // Resume EventTap and reset processing state
            resumeCallback()
            
            SoundPlayer.shared.playSuccess()
            Log.d("LayoutSwitchAction", "Layout switch completed successfully")
        }
    }
    
    // Legacy synchronous method for backward compatibility
    func performHotkey() {
        performHotkeyAsync(suspendCallback: {}, resumeCallback: {})
    }
    
    private func simulateKeyCombination(_ modifiers: CGEventFlags, _ keyCode: CGKeyCode) -> Bool {
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        
        keyDownEvent.flags = modifiers
        keyUpEvent.flags = modifiers
        
        // Use .cgSessionEventTap for proper event delivery to active application
        keyDownEvent.post(tap: .cgSessionEventTap)
        keyUpEvent.post(tap: .cgSessionEventTap)
        
        return true
    }
}

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
            
            let itemData = PasteboardItemData(types: types, data: dataDict)
            itemsData.append(itemData)
        }
        
        Log.d("PasteboardManager", "Backed up \(itemsData.count) pasteboard items with \(itemsData.reduce(0) { $0 + $1.data.count }) data types")
        
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
                Log.d("PasteboardManager", "Restored \(newItems.count) pasteboard items")
            } else if let fallbackString = backup.fallbackString {
                pasteboard.setString(fallbackString, forType: .string)
                Log.d("PasteboardManager", "Restored fallback string (items failed)")
            }
        } else if let fallbackString = backup.fallbackString {
            pasteboard.setString(fallbackString, forType: .string)
            Log.d("PasteboardManager", "Restored fallback string")
        }
    }
}

// Placeholder classes for missing actions referenced in HotkeyManager
final class AITransformAction {
    func perform(for prompt: Any) {
        Log.d("AITransformAction", "AI transform not implemented")
    }
}

final class CaseTransformAction {
    func performHotkey() {
        Log.d("CaseTransformAction", "Case transform not implemented")
    }
}

// Placeholder struct for missing Prompt type
struct Prompt {
    let config: PromptConfig
}

struct PromptConfig {
    let hotkey: String
}
