import Foundation
import AppKit
import ApplicationServices

/// Universal Canva detection using multiple methods
/// Provides reliable detection of Canva web app through URL and pattern analysis
final class UniversalCanvaDetector {
    
    struct DetectionResult {
        let detected: Bool
        let confidence: Int
        let method: String
        let details: String
    }
    
    /// Main detection method - combines URL and pattern analysis
    static func detect() -> DetectionResult {
        Log.d("UniversalDetection", "🚀 Starting Universal Canva Detection...")
        
        // Primary method: URL-based detection
        if let urlResult = detectViaURL() {
            return urlResult
        }
        
        // Fallback method: Pattern analysis
        return detectViaPatterns()
    }
    
    // MARK: - URL-Based Detection (Primary)
    
    private static func detectViaURL() -> DetectionResult? {
        guard let url = extractURLFromBrowser() else {
            Log.d("UniversalDetection", "URL extraction failed - trying any app")
            return nil
        }
        
        if url.lowercased().contains("canva.com") {
            Log.d("UniversalDetection", "✅ DEFINITIVE: Canva detected via URL domain")
            return DetectionResult(
                detected: true,
                confidence: 100,
                method: "URL",
                details: "canva.com domain found"
            )
        } else {
            Log.d("UniversalDetection", "URL checked: '\(url)' - not Canva domain")
            return DetectionResult(
                detected: false,
                confidence: 0,
                method: "URL",
                details: "Non-Canva domain: \(url)"
            )
        }
    }
    
    private static func extractURLFromBrowser() -> String? {
        guard let frontmostApp = ApplicationDetector.currentApp else {
            return nil
        }
        
        Log.d("UniversalDetection", "Attempting URL extraction from app: \(ApplicationDetector.currentBundleID())")
        
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
    
    // MARK: - Pattern-Based Detection (Fallback)
    
    private static func detectViaPatterns() -> DetectionResult {
        guard let frontmostApp = ApplicationDetector.currentApp else {
            return DetectionResult(detected: false, confidence: 0, method: "Pattern", details: "No frontmost app")
        }
        
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        var windowsRef: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard windowsResult == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else {
            return DetectionResult(detected: false, confidence: 0, method: "Pattern", details: "Failed to get windows")
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
        
        // Confidence Thresholds (lowered for better detection)
        let moderateThreshold = 15  // Reduced from 25 to be less restrictive
        let isCanvaDetected = bestScore >= moderateThreshold
        
        if isCanvaDetected {
            let confidenceLevel = bestScore >= 100 ? "DEFINITIVE" :
                                 bestScore >= 50 ? "HIGH" :
                                 bestScore >= 25 ? "MODERATE" : "LOW"
            
            Log.d("UniversalDetection", "✅ \(confidenceLevel): Canva detected via patterns")
            Log.d("UniversalDetection", "Best match: '\(bestTitle)' (Score: \(bestScore))")
            Log.d("UniversalDetection", "Indicators: \(bestIndicators)")
            
            return DetectionResult(
                detected: true,
                confidence: bestScore,
                method: "Pattern",
                details: "Score: \(bestScore), Indicators: \(bestIndicators.joined(separator: ", "))"
            )
        } else {
            Log.d("UniversalDetection", "❌ Canva not detected - insufficient pattern confidence")
            Log.d("UniversalDetection", "Best score: \(bestScore) (threshold: \(moderateThreshold))")
            
            return DetectionResult(
                detected: false,
                confidence: bestScore,
                method: "Pattern",
                details: "Insufficient confidence: \(bestScore)/\(moderateThreshold)"
            )
        }
    }
    
    private static func analyzeCanvaPatterns(_ title: String) -> (score: Int, indicators: [String]) {
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
}
