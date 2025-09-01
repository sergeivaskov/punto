import Foundation
import Carbon
import ApplicationServices

/// Исполнитель автоматических замен текста
public final class ReplacementExecutor {
    private var isExecuting = false
    private var suspendCallback: (() -> Void)?
    private var resumeCallback: (() -> Void)?
    
    public init() {}
    
    /// Установка callbacks для suspend/resume EventTap
    public func setSuspendResumeCallbacks(suspend: @escaping () -> Void, resume: @escaping () -> Void) {
        suspendCallback = suspend
        resumeCallback = resume
    }
    
    /// Replacement execution with pre-calculated parameters
    public func executeReplacement(originalLength: Int, replacementText: String, targetLayout: KeyboardLayout, completion: @escaping (Bool) -> Void) {
        guard !isExecuting else {
            Log.d("ReplacementExecutor", "Already executing replacement, ignoring request")
            completion(false)
            return
        }
        
        guard originalLength > 0 && !replacementText.isEmpty else {
            Log.d("ReplacementExecutor", "Invalid parameters")
            completion(false)
            return
        }
        
        Log.d("ReplacementExecutor", "Starting replacement: delete \(originalLength) → '\(replacementText)'")
        isExecuting = true
        suspendCallback?()
        
        DispatchQueue.main.async { [weak self] in
            self?.performReplacement(deleteCount: originalLength, replacementText: replacementText, targetLayout: targetLayout, completion: completion)
        }
    }
    
    private func performReplacement(deleteCount: Int, replacementText: String, targetLayout: KeyboardLayout, completion: @escaping (Bool) -> Void) {
        let startTime = Date()
        Log.d("ReplacementExecutor", "Starting atomic replacement")
        
        guard deleteCharacters(count: deleteCount) else {
            Log.d("ReplacementExecutor", "Delete failed")
            return finishReplacement(success: false, completion: completion)
        }
        
        guard typeText(replacementText) else {
            Log.d("ReplacementExecutor", "Type failed")
            return finishReplacement(success: false, completion: completion)
        }
        
        if !switchToLayout(targetLayout) {
            Log.d("ReplacementExecutor", "Layout switch warning")
        }
        
        SoundPlayer.shared.playWordChanged()
        
        let executionTime = Date().timeIntervalSince(startTime)
        Log.d("ReplacementExecutor", "Completed in \(Int(executionTime * 1000))ms")
        finishReplacement(success: true, completion: completion)
    }
    
    private func switchToLayout(_ layout: KeyboardLayout) -> Bool {
        layout == .enUS ? InputSourceManager.switchToEnglish() : InputSourceManager.switchToRussian()
    }
    
    private func deleteCharacters(count: Int) -> Bool {
        for i in 0..<count {
            guard sendKeyEvent(keyCode: CGKeyCode(kVK_Delete), keyDown: true),
                  sendKeyEvent(keyCode: CGKeyCode(kVK_Delete), keyDown: false) else {
                Log.d("ReplacementExecutor", "Delete failed at \(i + 1)/\(count)")
                return false
            }
        }
        return true
    }
    
    private func typeText(_ text: String) -> Bool {
        for char in text {
            guard typeCharacter(char) else {
                Log.d("ReplacementExecutor", "Type failed: '\(char)'")
                return false
            }
        }
        return true
    }
    
    private func typeCharacter(_ character: Character) -> Bool {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { return false }
        
        var unicodeString = Array(String(character).utf16)
        event.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)
        
        event.post(tap: .cghidEventTap)
        event.type = .keyUp
        event.post(tap: .cghidEventTap)
        return true
    }
    
    private func sendKeyEvent(keyCode: CGKeyCode, keyDown: Bool) -> Bool {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }
    
    private func finishReplacement(success: Bool, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.resumeCallback?()
            self?.isExecuting = false
            completion(success)
        }
    }
    
    public func cancel() {
        if isExecuting {
            Log.d("ReplacementExecutor", "Cancelling")
            finishReplacement(success: false) { _ in }
        }
    }
}
