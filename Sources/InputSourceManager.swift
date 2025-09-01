import Foundation
import Carbon

/// Input Source Manager for switching system keyboard layouts
final class InputSourceManager {
    
    enum InputSourceID: String {
        case usEnglish = "com.apple.keylayout.ABC"
        case usEnglishAlternate = "com.apple.keylayout.US" 
        case russianPhonetic = "com.apple.keylayout.Russian-Phonetic"
        case russian = "com.apple.keylayout.Russian"
    }
    
    /// Get current active input source ID
    static func getCurrentInputSource() -> String? {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        
        guard let sourceID = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else {
            return nil
        }
        
        return Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
    }
    
    /// Switch to specific input source
    static func switchToInputSource(_ sourceID: InputSourceID) -> Bool {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            Log.d("InputSourceManager", "Failed to get input sources list")
            return false
        }
        
        for source in sources {
            guard let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                continue
            }
            
            let currentID = Unmanaged<CFString>.fromOpaque(id).takeUnretainedValue() as String
            
            if currentID == sourceID.rawValue {
                let result = TISSelectInputSource(source)
                let success = result == noErr
                
                if success {
                    Log.d("InputSourceManager", "Successfully switched to input source: \(sourceID.rawValue)")
                } else {
                    Log.d("InputSourceManager", "Failed to switch to input source: \(sourceID.rawValue), error: \(result)")
                }
                
                return success
            }
        }
        
        Log.d("InputSourceManager", "Input source not found: \(sourceID.rawValue)")
        return false
    }
    
    /// Switch to English layout
    static func switchToEnglish() -> Bool {
        // Try ABC first (most common), fallback to US if not available
        if switchToInputSource(.usEnglish) {
            return true
        }
        return switchToInputSource(.usEnglishAlternate)
    }
    
    /// Switch to Russian layout (prefer standard Russian over Phonetic)
    static func switchToRussian() -> Bool {
        // Try standard Russian first, fallback to Phonetic if not available
        if switchToInputSource(.russian) {
            return true
        }
        return switchToInputSource(.russianPhonetic)
    }
    
    /// Determine target layout based on converted text
    static func determineTargetLayout(from originalText: String, to convertedText: String) -> InputSourceID? {
        // Enhanced heuristic: analyze both letters and special characters
        let cyrillicCharacterSet = CharacterSet(charactersIn: "а"..."я")
            .union(CharacterSet(charactersIn: "А"..."Я"))
            .union(CharacterSet(charactersIn: "ё"))
            .union(CharacterSet(charactersIn: "Ё"))
            // Add Russian special characters from mapping
            .union(CharacterSet(charactersIn: "ёЁжЖэЭхХъЪбБюЮ"))
            .union(CharacterSet(charactersIn: "\"№%:,.;()"))
        
        let latinCharacterSet = CharacterSet(charactersIn: "a"..."z")
            .union(CharacterSet(charactersIn: "A"..."Z"))
            // Add English special characters from mapping  
            .union(CharacterSet(charactersIn: "`~[];'{}\"<>"))
            .union(CharacterSet(charactersIn: "@#$%^&*()"))
        
        let cyrillicCount = convertedText.unicodeScalars.filter { cyrillicCharacterSet.contains($0) }.count
        let latinCount = convertedText.unicodeScalars.filter { latinCharacterSet.contains($0) }.count
        
        if cyrillicCount > latinCount {
            return .russian
        } else if latinCount > cyrillicCount {
            return .usEnglish
        }
        
        return nil // Ambiguous or equal counts
    }
    
    /// Switch layout based on converted text analysis
    static func switchBasedOnConvertedText(originalText: String, convertedText: String) {
        guard let targetLayout = determineTargetLayout(from: originalText, to: convertedText) else {
            Log.d("InputSourceManager", "Could not determine target layout for conversion")
            return
        }
        
        let success = switchToInputSource(targetLayout)
        Log.d("InputSourceManager", "Layout switch after conversion: \(success ? "success" : "failed") to \(targetLayout.rawValue)")
    }
    
    /// Debug method to list all available input sources
    static func listAllInputSources() {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            Log.d("InputSourceManager", "Failed to get input sources list")
            return
        }
        
        Log.d("InputSourceManager", "Available input sources:")
        for source in sources {
            guard let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                continue
            }
            
            let currentID = Unmanaged<CFString>.fromOpaque(id).takeUnretainedValue() as String
            Log.d("InputSourceManager", "- \(currentID)")
        }
    }
}
