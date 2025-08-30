import Foundation
import AppKit
import Carbon

/// Clipboard processing service
/// Handles text conversion and clipboard operations with pasteboard backup/restore
final class ClipboardProcessor {
    
    private let layoutConverter = QwertyJcukenLayoutConverter()
    
    struct ProcessingResult {
        let success: Bool
        let reason: String
        let originalText: String?
        let convertedText: String?
    }
    
    /// Process clipboard content with validation and conversion
    func processClipboardContent(
        pasteboardBackup: PasteboardManager.PasteboardBackup,
        previousClipboardText: String,
        completion: @escaping (ProcessingResult) -> Void
    ) {
        // Read and analyze text from clipboard
        guard let clipboardText = NSPasteboard.general.string(forType: .string),
              !clipboardText.isEmpty else {
            Log.d("ClipboardProcessor", "No text in clipboard")
            completion(ProcessingResult(
                success: false,
                reason: "No text in clipboard",
                originalText: nil,
                convertedText: nil
            ))
            return
        }
        
        // Context Gating: Check if clipboard actually changed (i.e., there was a selection)
        guard clipboardText != previousClipboardText else {
            Log.d("ClipboardProcessor", "No selection detected - clipboard unchanged")
            completion(ProcessingResult(
                success: false,
                reason: "No selection detected - clipboard unchanged, cancelling operation",
                originalText: clipboardText,
                convertedText: nil
            ))
            return
        }
        
        // Basic text validation
        let basicValidation = ContextValidator.validateBasicRequirements(clipboardText)
        guard basicValidation.valid else {
            Log.d("ClipboardProcessor", "Basic validation failed: \(basicValidation.reason)")
            completion(ProcessingResult(
                success: false,
                reason: basicValidation.reason,
                originalText: clipboardText,
                convertedText: nil
            ))
            return
        }
        
        // Context-specific content validation
        let contentValidation = ContextValidator.validateContent(clipboardText)
        guard contentValidation.allowed else {
            Log.d("ClipboardProcessor", "Content validation failed: \(contentValidation.reason)")
            completion(ProcessingResult(
                success: false,
                reason: contentValidation.reason,
                originalText: clipboardText,
                convertedText: nil
            ))
            return
        }
        
        // Convert to opposite layout
        let convertedText = layoutConverter.convertToOppositeLayout(clipboardText)
        
        Log.d("ClipboardProcessor", "Converting '\(clipboardText)' -> '\(convertedText)'")
        
        // Set converted text to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(convertedText, forType: .string)
        
        completion(ProcessingResult(
            success: true,
            reason: "Text converted successfully",
            originalText: clipboardText,
            convertedText: convertedText
        ))
    }
    
    /// Simulate key combination (Cmd+C, Cmd+V)
    func simulateKeyCombination(_ modifiers: CGEventFlags, _ keyCode: CGKeyCode) -> Bool {
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
    
    /// Copy selection to clipboard (Cmd+C)
    func copySelection() -> Bool {
        let success = simulateKeyCombination(.maskCommand, CGKeyCode(kVK_ANSI_C))
        if success {
            Log.d("ClipboardProcessor", "Copy command sent successfully")
        } else {
            Log.d("ClipboardProcessor", "Failed to send copy command")
        }
        return success
    }
    
    /// Paste from clipboard (Cmd+V)
    func pasteContent() -> Bool {
        let success = simulateKeyCombination(.maskCommand, CGKeyCode(kVK_ANSI_V))
        if success {
            Log.d("ClipboardProcessor", "Paste command sent successfully")
        } else {
            Log.d("ClipboardProcessor", "Failed to send paste command")
        }
        return success
    }
    
    /// Get current clipboard text
    func getCurrentClipboardText() -> String {
        return NSPasteboard.general.string(forType: .string) ?? ""
    }
}
