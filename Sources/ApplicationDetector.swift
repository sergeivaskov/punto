import Foundation
import AppKit

/// Universal application detection service
/// Provides centralized app categorization and detection logic
final class ApplicationDetector {
    
    enum AppCategory {
        case browser
        case canvas
        case desktop
    }
    
    private static let browserBundleIDs = [
        "com.google.Chrome",
        "com.apple.Safari", 
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "com.brave.Browser",
        // Electron-based browsers and apps that may contain web content
        "com.github.atom",
        "com.microsoft.VSCode",
        "com.discord.Discord",
        "com.tinyspeck.slackmacgap",
        "com.spotify.client"
    ]
    
    private static let canvasBundleIDs = [
        "com.figma.Desktop",
        "com.adobe.illustrator",
        "com.adobe.Photoshop",
        "com.bohemiancoding.sketch3",
        "com.adobe.AfterEffects",
        "com.adobe.InDesign"
    ]
    
    private static let blockedBundleIDs = [
        "com.adobe.illustrator"  // Completely blocked due to complex Canvas operations
    ]
    
    /// Get current frontmost application
    static var currentApp: NSRunningApplication? {
        return NSWorkspace.shared.frontmostApplication
    }
    
    /// Detect application category
    static func detectCategory() -> AppCategory {
        guard let app = currentApp else {
            Log.d("AppDetector", "No frontmost application")
            return .desktop
        }
        
        let bundleID = app.bundleIdentifier ?? ""
        
        if browserBundleIDs.contains(bundleID) {
            Log.d("AppDetector", "Browser detected: \(bundleID)")
            return .browser
        }
        
        if canvasBundleIDs.contains(bundleID) {
            Log.d("AppDetector", "Canvas app detected: \(bundleID)")
            return .canvas
        }
        
        Log.d("AppDetector", "Desktop app detected: \(bundleID)")
        return .desktop
    }
    
    /// Check if current app is a browser
    static func isBrowser() -> Bool {
        guard let bundleID = currentApp?.bundleIdentifier else { return false }
        return browserBundleIDs.contains(bundleID)
    }
    
    /// Check if current app is a Canvas application
    static func isCanvas() -> Bool {
        guard let bundleID = currentApp?.bundleIdentifier else { return false }
        return canvasBundleIDs.contains(bundleID)
    }
    
    /// Check if current app is completely blocked
    static func isBlocked() -> Bool {
        guard let bundleID = currentApp?.bundleIdentifier else { return false }
        let blocked = blockedBundleIDs.contains(bundleID)
        
        if blocked {
            Log.d("AppDetector", "Blocked application detected: \(bundleID)")
        }
        
        return blocked
    }
    
    /// Get current app bundle ID for logging
    static func currentBundleID() -> String {
        return currentApp?.bundleIdentifier ?? "unknown"
    }
}
