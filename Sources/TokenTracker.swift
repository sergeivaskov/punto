import Foundation
import Carbon
import ApplicationServices

/// Компонент для realtime анализа клавиатурного ввода и токенизации слов
public final class TokenTracker {
    private var currentToken: String = ""
    private var lastBundleID: String = ""
    private static let maxTokenLength = 100
    
    // Unified mapping: keyCode -> reset reason
    private static let interruptionMap: [CGKeyCode: String] = [
        // Navigation
        CGKeyCode(kVK_LeftArrow): "navigation", CGKeyCode(kVK_RightArrow): "navigation",
        CGKeyCode(kVK_UpArrow): "navigation", CGKeyCode(kVK_DownArrow): "navigation",
        CGKeyCode(kVK_Home): "navigation", CGKeyCode(kVK_End): "navigation",
        CGKeyCode(kVK_PageUp): "navigation", CGKeyCode(kVK_PageDown): "navigation",
        // Editing
        CGKeyCode(kVK_Delete): "editing", CGKeyCode(kVK_ForwardDelete): "editing",
        // Control
        CGKeyCode(kVK_Tab): "control", CGKeyCode(kVK_Return): "control", CGKeyCode(kVK_Escape): "control"
    ]
    
    /// Обработка keyDown события для токенизации
    public func handleKeyDown(_ event: CGEvent, isProcessing: Bool) {
        guard !isProcessing else { return }
        
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        
        // Context change или interruption key → reset
        if checkContextChange() { return resetToken("focus change") }
        if let reason = Self.interruptionMap[keyCode] { return resetToken(reason) }
        
        // Modifiers → skip
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        guard modifiers.intersection(event.flags).isEmpty else { return }
        
        // Space → complete token
        if keyCode == CGKeyCode(kVK_Space) { return completeToken() }
        
        // Accumulate character if valid context
        guard isValidContext(), let char = extractCharacter(from: event) else { return }
        accumulateCharacter(char)
    }
    
    private func extractCharacter(from event: CGEvent) -> String? {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }
        
        var chars = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &chars)
        
        let char = String(utf16CodeUnits: chars, count: length)
        return char.rangeOfCharacter(from: .whitespacesAndNewlines) == nil ? char : nil
    }
    
    private func accumulateCharacter(_ char: String) {
        guard currentToken.count < Self.maxTokenLength else { return resetToken("length limit") }
        currentToken += char
    }
    
    private func completeToken() {
        guard !currentToken.isEmpty else { return }
        Log.d("TokenTracker", "🔤 TOKEN COMPLETED: '\(currentToken)'")
        currentToken = ""
    }
    
    private func resetToken(_ reason: String) {
        guard !currentToken.isEmpty else { return }
        Log.d("TokenTracker", "⚡ TOKEN RESET: '\(currentToken)' (by \(reason))")
        currentToken = ""
    }
    
    private func isValidContext() -> Bool {
        return !ApplicationDetector.isBlocked() && !ApplicationDetector.isCanvas()
    }
    
    public func forceReset() {
        guard !currentToken.isEmpty else { return }
        Log.d("TokenTracker", "🔄 TOKEN DISCARDED: '\(currentToken)' (force reset)")
        currentToken = ""
    }
    
    private func checkContextChange() -> Bool {
        let bundleID = ApplicationDetector.currentBundleID()
        defer { lastBundleID = bundleID }
        return !lastBundleID.isEmpty && bundleID != lastBundleID
    }
}
