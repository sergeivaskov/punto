import Foundation
import Carbon
import ApplicationServices
import QuartzCore

/// Компонент для realtime анализа клавиатурного ввода и токенизации слов
public final class TokenTracker {
    private var currentToken: String = ""
    private var lastBundleID: String = ""
    private var isPostReplacement: Bool = false
    private var lastFocusChangeTime: CFTimeInterval = 0
    private var isPendingSpaceAnalysis: Bool = false
    private let layoutConverter = QwertyJcukenLayoutConverter()
    
    private static let maxTokenLength = 100
    private static let focusChangeGracePeriod: CFTimeInterval = 0.3
    
    // Unified interruption mapping
    private static let interruptionMap: [CGKeyCode: String] = [
        CGKeyCode(kVK_LeftArrow): "nav", CGKeyCode(kVK_RightArrow): "nav", CGKeyCode(kVK_UpArrow): "nav", CGKeyCode(kVK_DownArrow): "nav",
        CGKeyCode(kVK_Home): "nav", CGKeyCode(kVK_End): "nav", CGKeyCode(kVK_PageUp): "nav", CGKeyCode(kVK_PageDown): "nav",
        CGKeyCode(kVK_Delete): "edit", CGKeyCode(kVK_ForwardDelete): "edit", CGKeyCode(kVK_Tab): "ctrl", 
        CGKeyCode(kVK_Return): "ctrl", CGKeyCode(kVK_Escape): "ctrl"
    ]
    
    private var currentLayout: KeyboardLayout {
        InputSourceManager.getCurrentInputSource()?.contains("Russian") == true ? .ruRU : .enUS
    }
    
    public func handleKeyDown(_ event: CGEvent, isProcessing: Bool) {
        guard !isProcessing else { return }
        
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        handleFocusChangeIfNeeded()
        
        if let reason = Self.interruptionMap[keyCode] { return clearToken(reason) }
        
        // Специальная обработка пробела для коротких токенов
        if keyCode == CGKeyCode(kVK_Space) {
            if currentToken.count < 3 && !currentToken.isEmpty {
                Log.d("TokenTracker", "🔤 SHORT TOKEN '\(currentToken)': pending space analysis")
                isPendingSpaceAnalysis = true
                return // НЕ очищаем токен пока
            } else {
                return clearToken("space", isCompletion: true)
            }
        }
        
        let skipModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        guard skipModifiers.intersection(event.flags).isEmpty,
              isValidContextPublic(),
              let char = extractCharacter(keyCode: keyCode, isShift: event.flags.contains(.maskShift)) else { return }
        
        guard currentToken.count < Self.maxTokenLength else { return clearToken("length") }
        currentToken += char
        Log.d("TokenTracker", "📝 '\(currentToken)'[\(currentToken.count)]")
    }
    
    private func extractCharacter(keyCode: CGKeyCode, isShift: Bool) -> String? {
        guard let baseChar = layoutConverter.extractCharacterFromKeycode(keyCode, layout: currentLayout) else { return nil }
        let char = isShift ? baseChar.uppercased() : baseChar
        guard char.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        Log.d("TokenTracker", "🔤 \(keyCode)→'\(char)'")
        return char
    }
    
    private func clearToken(_ reason: String, isCompletion: Bool = false) {
        if !currentToken.isEmpty {
            Log.d("TokenTracker", "\(isCompletion ? "🔤 COMPLETED" : "⚡ RESET"): '\(currentToken)' (\(reason))")
            currentToken = ""
        }
        if isPostReplacement {
            isPostReplacement = false
            Log.d("TokenTracker", "✅ ANALYSIS RE-ENABLED")
        }
        if isPendingSpaceAnalysis {
            isPendingSpaceAnalysis = false
            Log.d("TokenTracker", "🔤 SPACE ANALYSIS: cancelled (\(reason))")
        }
    }
    
    /// Определение secure/password полей через Accessibility API
    private func isSecureField() -> Bool {
        let systemElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focused = focusedElement else {
            return false // Fallback: allow operation if AX fails
        }
        
        let focusedAXElement = focused as! AXUIElement
        var role: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(focusedAXElement, kAXRoleAttribute as CFString, &role) == .success,
              let roleString = role as? String else {
            return false // Fallback: allow operation if role unavailable
        }
        
        let isSecure = roleString == "AXSecureTextField"
        if isSecure {
            Log.d("TokenTracker", "🔒 SECURE FIELD: Blocking in \(ApplicationDetector.currentBundleID())")
        }
        return isSecure
    }
    
    private func handleFocusChangeIfNeeded() {
        let bundleID = ApplicationDetector.currentBundleID()
        guard !lastBundleID.isEmpty && bundleID != lastBundleID else {
            lastBundleID = bundleID
            return
        }
        
        lastFocusChangeTime = CACurrentMediaTime()
        Log.d("TokenTracker", "🔄 '\(lastBundleID)' → '\(bundleID)' (grace period)")
        
        if !currentToken.isEmpty {
            Log.d("TokenTracker", "⚡ RESET: '\(currentToken)' (focus change)")
            currentToken = ""
        }
        if isPostReplacement {
            isPostReplacement = false
            Log.d("TokenTracker", "✅ ANALYSIS RE-ENABLED")
        }
        lastBundleID = bundleID
    }
    
    // MARK: - Public API
    
    /// Получение текущего токена для автозамены
    public func getCurrentToken() -> String { currentToken }
    
    public func isValidContextPublic() -> Bool {
        let isInGracePeriod = (CACurrentMediaTime() - lastFocusChangeTime) < Self.focusChangeGracePeriod
        let isSecure = isSecureField()
        if isInGracePeriod && !isSecure {
            Log.d("TokenTracker", "⏰ GRACE PERIOD: keystroke allowed")
        }
        return !isSecure
    }
    
    public func isPostReplacementMode() -> Bool { isPostReplacement }
    public func forceReset() { clearToken("force") }
    
    public func updateTokenAfterReplacement(newText: String, originalToken: String) {
        Log.d("TokenTracker", "🔄 '\(originalToken)' → '\(newText)' (analysis disabled)")
        currentToken = newText
        isPostReplacement = true
    }
    
    // MARK: - Short Token Space Analysis Support
    
    public func isPendingSpaceAnalysisActive() -> Bool { isPendingSpaceAnalysis }
    
    public func completeSpaceAnalysis(success: Bool) {
        guard isPendingSpaceAnalysis else { return }
        
        if success {
            Log.d("TokenTracker", "🔤 SPACE ANALYSIS: completed - clearing token")
            clearToken("space-replacement", isCompletion: true)
        } else {
            Log.d("TokenTracker", "🔤 SPACE ANALYSIS: no replacement - clearing token")
            clearToken("space-normal", isCompletion: true)
        }
    }
}