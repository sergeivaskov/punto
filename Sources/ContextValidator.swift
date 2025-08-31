import Foundation
import AppKit
import ApplicationServices

/// Context validation service
/// Provides content validation rules based on application type and context
final class ContextValidator {
    
    struct ValidationRules {
        let maxLength: Int
        let allowMultiline: Bool
        let appType: String
    }
    
    struct ValidationResult {
        let allowed: Bool
        let reason: String
        let appliedRules: ValidationRules
    }
    
    /// Validate text content based on current application context
    static func validateContent(_ text: String) -> ValidationResult {
        let rules = determineValidationRules()
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMultipleLines = text.contains("\n") || text.contains("\r")
        
        // Check text length
        if trimmedText.count > rules.maxLength {
            Log.d("ContextValidator", "\(rules.appType): Text too long (\(trimmedText.count) chars, max \(rules.maxLength)) - likely data object")
            return ValidationResult(
                allowed: false,
                reason: "Text too long (\(trimmedText.count) chars, max \(rules.maxLength)) - likely data object, not text editing",
                appliedRules: rules
            )
        }
        
        // Check multiline content for Canvas apps
        if !rules.allowMultiline && hasMultipleLines && trimmedText.count < rules.maxLength {
            Log.d("ContextValidator", "\(rules.appType): Multiline content detected - likely structured data")
            return ValidationResult(
                allowed: false,
                reason: "Multiline content detected - likely structured data, not text editing",
                appliedRules: rules
            )
        }
        
        Log.d("ContextValidator", "\(rules.appType): Content validation passed (\(trimmedText.count) chars)")
        return ValidationResult(
            allowed: true,
            reason: "Content validation passed (\(trimmedText.count) chars)",
            appliedRules: rules
        )
    }
    
    /// Determine validation rules based on current application context
    private static func determineValidationRules() -> ValidationRules {
        let appCategory = ApplicationDetector.detectCategory()
        
        switch appCategory {
        case .canvas:
            // Strict validation for Canvas applications
            return ValidationRules(
                maxLength: 50,
                allowMultiline: false,
                appType: "Canvas app"
            )
            
        case .browser:
            // General browser validation for all browsers
            return ValidationRules(
                maxLength: 100,
                allowMultiline: true,
                appType: "Browser app"
            )
            
        case .desktop:
            // No validation for desktop applications
            return ValidationRules(
                maxLength: Int.max,
                allowMultiline: true,
                appType: "Desktop app"
            )
        }
    }
    
    /// Validate basic text requirements
    static func validateBasicRequirements(_ text: String) -> (valid: Bool, reason: String) {
        // Check if text is empty
        guard !text.isEmpty else {
            return (false, "No text in clipboard")
        }
        
        // Allow all non-empty text - let LayoutConverter decide what's convertible
        // This enables conversion of special characters, punctuation, numbers, etc.
        return (true, "Basic requirements met")
    }
}
