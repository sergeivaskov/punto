import Foundation
import AppKit
import Carbon

Log.d("PuntoPunto", "Starting PuntoPunto application")

// Проверка разрешений Accessibility
func checkAccessibilityPermissions() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
    let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    
    if !isTrusted {
        Log.d("PuntoPunto", "Accessibility permissions not granted")
        
        let alert = NSAlert()
        alert.messageText = "Требуются разрешения"
        alert.informativeText = "PuntoPunto требует разрешения 'Универсальный доступ' для работы с клавиатурой. Пожалуйста, включите разрешение в Системные настройки > Конфиденциальность и безопасность > Универсальный доступ."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        
        return false
    }
    
    return true
}

// Основной класс приложения
class PuntoPuntoApp: NSObject, NSApplicationDelegate {
    private let hotkeyManager = HotkeyManager()
    private var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Log.d("PuntoPunto", "Application did finish launching")
        
        // Проверка разрешений
        guard checkAccessibilityPermissions() else {
            Log.d("PuntoPunto", "Accessibility permissions required - exiting")
            NSApp.terminate(nil)
            return
        }
        
        // Асинхронная инициализация с правильной последовательностью
        Task {
            await initializeAsync()
        }
    }
    
    /// Асинхронная инициализация компонентов в правильном порядке
    private func initializeAsync() async {
        // 1. Загрузка словарей для автозамены (КРИТИЧНО: до регистрации hotkeys)
        Log.d("PuntoPunto", "🔄 Loading dictionaries...")
        await DictionaryManager.shared.loadDictionaries()
        Log.d("PuntoPunto", "✅ Dictionaries ready")
        
        // 2. UI-related операции должны выполняться в main thread
        await MainActor.run {
            // Debug: список доступных input sources
            InputSourceManager.listAllInputSources()
            
            // Регистрация Option клавиши ТОЛЬКО после готовности словарей
            hotkeyManager.registerLayoutSwitch()
            Log.d("PuntoPunto", "✅ Auto-replacement enabled")
            
            // Создание иконки в системном трее (требует main thread)
            setupStatusItem()
            
            Log.d("PuntoPunto", "PuntoPunto successfully initialized and ready")
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        Log.d("PuntoPunto", "Application will terminate")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Приложение продолжает работать в фоне
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Используем системную иконку для переключения
            button.image = NSImage(systemSymbolName: "character.textbox", accessibilityDescription: "PuntoPunto")
            button.toolTip = "PuntoPunto - Переключение раскладки (Option)"
        }
        
        // Создание меню
        let menu = NSMenu()
        
        let aboutItem = NSMenuItem(title: "О программе", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Выйти", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        
        Log.d("PuntoPunto", "Status item created")
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "PuntoPunto"
        alert.informativeText = "Переключение раскладки выделенного текста.\n\nИспользуйте клавишу Option для конвертации между английской и русской раскладками."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func quitApp() {
        Log.d("PuntoPunto", "Quitting application")
        NSApp.terminate(nil)
    }
}

// Инициализация и запуск приложения
let app = NSApplication.shared
let delegate = PuntoPuntoApp()
app.delegate = delegate

// Скрыть иконку из дока (приложение работает в фоне)
app.setActivationPolicy(.accessory)

Log.d("PuntoPunto", "Starting run loop")
app.run()
