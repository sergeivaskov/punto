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
    
    private func getElementRole(_ element: AXUIElement) -> String? {
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        
        guard roleResult == .success, let role = roleValue as? String else {
            return nil
        }
        
        return role
    }
    
    private func isBrowserApplication() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        
        let browserBundleIDs = [
            "com.google.Chrome",
            "com.apple.Safari", 
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.operasoftware.Opera",
            "com.brave.Browser"
        ]
        
        return browserBundleIDs.contains(frontmostApp.bundleIdentifier ?? "")
    }
    
    private func isCanvasApplication() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        
        let canvasBundleIDs = [
            "com.figma.Desktop",
            "com.adobe.illustrator",
            "com.adobe.Photoshop",
            "com.bohemiancoding.sketch3",
            "com.adobe.AfterEffects",
            "com.adobe.InDesign"
        ]
        
        return canvasBundleIDs.contains(frontmostApp.bundleIdentifier ?? "")
    }
    
    private func extractURLFromBrowser() -> String? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Method 1: Try focused element URL
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if focusResult == .success, let focused = focusedElement {
            var urlRef: CFTypeRef?
            let urlResult = AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXURLAttribute as CFString, &urlRef)
            
            if urlResult == .success, let url = urlRef as? String, !url.isEmpty {
                Log.d("UniversalDetection", "URL extracted from focused element: '\(url)'")
                return url
            }
        }
        
        // Method 2: Try main window URL
        var windowsRef: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        if windowsResult == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
            for window in windows {
                var urlRef: CFTypeRef?
                let urlResult = AXUIElementCopyAttributeValue(window, kAXURLAttribute as CFString, &urlRef)
                
                if urlResult == .success, let url = urlRef as? String, !url.isEmpty {
                    Log.d("UniversalDetection", "URL extracted from window: '\(url)'")
                    return url
                }
            }
        }
        
        Log.d("UniversalDetection", "URL extraction failed - no URL available")
        return nil
    }
    
    private func analyzeCanvaPatterns(_ title: String) -> (score: Int, indicators: [String]) {
        let title_lower = title.lowercased()
        var score = 0
        var indicators: [String] = []
        
        // Tier 1: Direct Canva indicators (high confidence)
        let directIndicators = ["canva", "canva.com"]
        for indicator in directIndicators {
            if title_lower.contains(indicator) {
                score += 100
                indicators.append("direct:\(indicator)")
            }
        }
        
        // Tier 2: Template/Design indicators (medium confidence)
        let templateIndicators = ["template", "design", "carousel", "poster", "banner", "flyer", "story"]
        for indicator in templateIndicators {
            if title_lower.contains(indicator) {
                score += 30
                indicators.append("template:\(indicator)")
            }
        }
        
        // Tier 3: Size patterns (medium confidence)
        let sizePatterns = ["1080 x 1350", "1920 x 1080", "800 x 800", "1200 x 1200", "x \\d+ px"]
        for pattern in sizePatterns {
            if title_lower.range(of: pattern, options: .regularExpression) != nil {
                score += 25
                indicators.append("size:\(pattern)")
            }
        }
        
        // Tier 4: Design-related terms (low confidence)
        let designTerms = ["px", "graphic", "visual", "layout", "creative"]
        for term in designTerms {
            if title_lower.contains(term) {
                score += 10
                indicators.append("design:\(term)")
            }
        }
        
        return (score, indicators)
    }
    
    private func isCanvaWebApp() -> Bool {
        // Universal Detection Framework
        Log.d("UniversalDetection", "🚀 Starting Universal Canva Detection...")
        
        // Check if current app is a browser
        guard isBrowserApplication() else {
            Log.d("UniversalDetection", "❌ Not a browser application")
            return false
        }
        
        var confidenceScore = 0
        var detectionMethods: [String] = []
        
        // Method 1: URL-Centric Detection (Primary - Highest Confidence)
        if let url = extractURLFromBrowser() {
            if url.lowercased().contains("canva.com") {
                confidenceScore += 100
                detectionMethods.append("URL:canva.com")
                Log.d("UniversalDetection", "✅ DEFINITIVE: Canva detected via URL domain")
                return true
            } else {
                Log.d("UniversalDetection", "URL checked: '\(url)' - not Canva domain")
            }
        }
        
        // Method 2: Enhanced Pattern Analysis (Fallback)
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            Log.d("UniversalDetection", "❌ No frontmost application")
            return false
        }
        
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        var windowsRef: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard windowsResult == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else {
            Log.d("UniversalDetection", "❌ Failed to get windows")
            return false
        }
        
        Log.d("UniversalDetection", "📊 Analyzing \(windows.count) windows for Canva patterns...")
        
        var bestScore = 0
        var bestIndicators: [String] = []
        var bestTitle = ""
        
        for (index, window) in windows.enumerated() {
            var titleRef: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            
            if titleResult == .success, let title = titleRef as? String, !title.isEmpty {
                let analysis = analyzeCanvaPatterns(title)
                
                Log.d("UniversalDetection", "Window \(index + 1): '\(title)' → Score: \(analysis.score), Indicators: \(analysis.indicators)")
                
                if analysis.score > bestScore {
                    bestScore = analysis.score
                    bestIndicators = analysis.indicators
                    bestTitle = title
                }
            }
        }
        
        // Confidence Thresholds
        let definitiveThreshold = 100  // Direct canva mention
        let highThreshold = 50         // Multiple strong patterns
        let moderateThreshold = 25     // Single strong pattern
        
        let isCanvaDetected = bestScore >= moderateThreshold
        
        if isCanvaDetected {
            let confidenceLevel = bestScore >= definitiveThreshold ? "DEFINITIVE" :
                                 bestScore >= highThreshold ? "HIGH" :
                                 bestScore >= moderateThreshold ? "MODERATE" : "LOW"
            
            Log.d("UniversalDetection", "✅ \(confidenceLevel): Canva detected via patterns")
            Log.d("UniversalDetection", "Best match: '\(bestTitle)' (Score: \(bestScore))")
            Log.d("UniversalDetection", "Indicators: \(bestIndicators)")
        } else {
            Log.d("UniversalDetection", "❌ Canva not detected - insufficient pattern confidence")
            Log.d("UniversalDetection", "Best score: \(bestScore) (threshold: \(moderateThreshold))")
        }
        
        return isCanvaDetected
    }
    
    private func isTextInputElement(_ role: String) -> Bool {
        let legitimateTextRoles = [
            "AXTextField", "AXTextArea", "AXComboBox", 
            "AXSearchField", "AXSecureTextField", "AXStaticText"
        ]
        
        // Standard text input elements
        if legitimateTextRoles.contains(role) {
            return true
        }
        
        // AXGroup in browsers can be rich text editors (Google Docs, etc.)
        if role == "AXGroup" && isBrowserApplication() {
            Log.d("LayoutSwitchAction", "AX: AXGroup detected in browser context - likely web text editor")
            return true
        }
        
        return false
    }
    
    private func checkSmartTextContext() -> Bool {
        // Block Adobe Illustrator completely due to complex Canvas operations
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           frontmostApp.bundleIdentifier == "com.adobe.illustrator" {
            Log.d("LayoutSwitchAction", "Adobe Illustrator detected - blocking all layout switch operations")
            return false
        }
        
        // Create system-wide accessibility object
        let systemElement = AXUIElementCreateSystemWide()
        
        // Get the focused UI element
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard focusResult == .success, let focused = focusedElement else {
            Log.d("LayoutSwitchAction", "AX: No focused element found, fallback to permissive mode")
            return true // Fallback to permissive behavior if AX fails
        }
        
        let focusedAXElement = focused as! AXUIElement
        
        // Get element role
        guard let role = getElementRole(focusedAXElement) else {
            Log.d("LayoutSwitchAction", "AX: Cannot determine element role, fallback to permissive mode")
            return true // Unknown role - allow operation
        }
        
        Log.d("LayoutSwitchAction", "AX: Focused element role: '\(role)' in app: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
        
        // Check if this is a legitimate text input element
        if isTextInputElement(role) {
            // It's a text input element - check for actual text selection
            var selectedText: CFTypeRef?
            let selectedResult = AXUIElementCopyAttributeValue(focusedAXElement, kAXSelectedTextAttribute as CFString, &selectedText)
            
            if selectedResult == .success,
               let text = selectedText as? String,
               !text.isEmpty {
                Log.d("LayoutSwitchAction", "AX: Text input with selection detected: '\(text.prefix(50))...'")
                return true // Legitimate text editing context with AX confirmation
            } else {
                Log.d("LayoutSwitchAction", "AX: Text input element but no AX selection detected, proceeding to clipboard validation")
                return true // Text element without AX selection - Canvas app fallback
            }
        } else {
            // Not a text input element (Canvas, Group, etc.)
            Log.d("LayoutSwitchAction", "AX: Non-text element role '\(role)' detected, likely Canvas operation")
            return false // Canvas or other non-text context
        }
    }
    
    func performHotkeyAsync(suspendCallback: @escaping () -> Void, resumeCallback: @escaping () -> Void) {
        Log.d("LayoutSwitchAction", "Starting async layout switch operation")
        
        // Context Gating: Check for smart text context using Enhanced AX Role Detection
        guard checkSmartTextContext() else {
            Log.d("LayoutSwitchAction", "Context Gating: No legitimate text context detected, cancelling operation")
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
        
        // Content Validation: prevent large data objects
        let isDesktopCanvas = isCanvasApplication()
        let isWebCanvas = isCanvaWebApp()
        let isBrowser = isBrowserApplication()
        
        // Strict validation for Canvas applications (Desktop + Web)
        if isDesktopCanvas || isWebCanvas {
            let trimmedText = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
            let maxLength = 50
            let hasMultipleLines = clipboardText.contains("\n") || clipboardText.contains("\r")
            let appType = isWebCanvas ? "Canva web app" : "Canvas app"
            
            // Block if text is too long (likely a data object, not edited text)
            if trimmedText.count > maxLength {
                Log.d("LayoutSwitchAction", "\(appType): Text too long (\(trimmedText.count) chars, max \(maxLength)) - likely data object, not text editing")
                PasteboardManager.restorePasteboard(pasteboardBackup)
                resumeCallback()
                return
            }
            
            // Block multiline content in short selections (likely tabular data)
            if hasMultipleLines && trimmedText.count < maxLength {
                Log.d("LayoutSwitchAction", "\(appType): Multiline content detected - likely structured data, not text editing")
                PasteboardManager.restorePasteboard(pasteboardBackup)
                resumeCallback()
                return
            }
            
            Log.d("LayoutSwitchAction", "\(appType): Content validation passed (\(trimmedText.count) chars)")
        }
        // Soft validation for general browser applications
        else if isBrowser {
            let trimmedText = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
            let maxLength = 100 // More lenient for general web apps
            
            // Block if text is too long (likely a UI element or data object)
            if trimmedText.count > maxLength {
                Log.d("LayoutSwitchAction", "Browser app: Text too long (\(trimmedText.count) chars, max \(maxLength)) - likely UI element or data object")
                PasteboardManager.restorePasteboard(pasteboardBackup)
                resumeCallback()
                return
            }
            
            Log.d("LayoutSwitchAction", "Browser app: Content validation passed (\(trimmedText.count) chars)")
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
