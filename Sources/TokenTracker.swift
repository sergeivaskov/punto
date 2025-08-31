import Foundation
import Carbon
import ApplicationServices

/// Компонент для realtime анализа клавиатурного ввода и токенизации слов
public final class TokenTracker {
    private var currentToken: String = ""
    private let maxTokenLength: Int = 1000
    
    public init() {}
    
    /// Обработка keyDown события для токенизации
    public func handleKeyDown(_ event: CGEvent, isProcessing: Bool) {
        // Пауза во время processing mode для предотвращения self-capture
        guard !isProcessing else {
            Log.d("TokenTracker", "Processing mode: pausing tokenization")
            return
        }
        
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // Игнорируем события с модификаторами (Cmd+A, Option+C и т.д.)
        let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        guard modifierMask.intersection(flags).isEmpty else {
            Log.d("TokenTracker", "Modifier detected: skipping accumulation")
            return
        }
        
        // Обработка пробела - логирование токена и сброс
        if keyCode == CGKeyCode(kVK_Space) {
            handleSpaceDetection()
            return
        }
        
        // Извлечение символа для накопления
        guard let character = extractCharacter(from: event) else {
            Log.d("TokenTracker", "Cannot extract character: skipping")
            return
        }
        
        // Проверка контекста для токенизации
        guard isValidTextContext() else {
            Log.d("TokenTracker", "Context invalid: skipping accumulation")
            return
        }
        
        // Накопление символа в токен
        accumulateCharacter(character)
    }
    
    /// Извлечение символа из CGEvent
    private func extractCharacter(from event: CGEvent) -> String? {
        // Получаем Unicode строку из события
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: nil)
        
        guard length > 0 else { return nil }
        
        var unicodeChars = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &unicodeChars)
        
        let character = String(utf16CodeUnits: unicodeChars, count: length)
        
        // Включаем только printable characters (буквы, цифры, спецсимволы)
        guard character.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines) == nil else {
            return nil
        }
        
        return character
    }
    
    /// Накопление символа в токен с защитой от overflow
    private func accumulateCharacter(_ character: String) {
        // Защита от memory overflow
        if currentToken.count >= maxTokenLength {
            Log.d("TokenTracker", "Token length limit reached: truncating and logging")
            handleSpaceDetection()
            return
        }
        
        currentToken += character
        Log.d("TokenTracker", "Token accumulated: '\(currentToken)' (length: \(currentToken.count))")
    }
    
    /// Обработка детекции пробела - логирование и сброс токена
    private func handleSpaceDetection() {
        // Логируем только non-empty токены
        guard !currentToken.isEmpty else {
            Log.d("TokenTracker", "Space detected: empty token, ignoring")
            return
        }
        
        Log.d("TokenTracker", "Space detected: logging token '\(currentToken)' and resetting")
        
        // Сброс токена для нового слова
        resetToken()
    }
    
    /// Сброс токена к начальному состоянию
    private func resetToken() {
        currentToken = ""
        Log.d("TokenTracker", "Token reset: ready for new word")
    }
    
    /// Проверка валидности текстового контекста
    private func isValidTextContext() -> Bool {
        // Базовая проверка на blocked приложения
        if ApplicationDetector.isBlocked() {
            return false
        }
        
        // Для Canvas приложений строгая валидация (оптимизированная через bundle ID)
        if ApplicationDetector.isCanvas() {
            Log.d("TokenTracker", "Canvas application detected: skipping tokenization")
            return false
        }
        
        // Разрешительный подход для большинства приложений
        return true
    }
    
    /// Принудительный сброс токена (для context changes, focus loss)
    public func forceReset() {
        if !currentToken.isEmpty {
            Log.d("TokenTracker", "Force reset: discarding token '\(currentToken)'")
            resetToken()
        }
    }
}
