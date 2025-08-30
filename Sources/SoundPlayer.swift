import Foundation
import AppKit

final class SoundPlayer {
    static let shared = SoundPlayer()
    private init() {}

    private var currentSound: NSSound?
    private static let soundEnabledKey = "SoundEnabled"

    private static var isEnabled: Bool {
        // По умолчанию звуки включены, если ключ отсутствует
        if UserDefaults.standard.object(forKey: soundEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: soundEnabledKey)
    }

    func playSuccess() {
        guard Self.isEnabled else { return }
        guard let url = locateSoundURL(named: "swap.mp3") else { return }
        if let sound = NSSound(contentsOf: url, byReference: true) {
            sound.volume = 0.2
            self.currentSound = sound
            sound.play()
            // Освобождаем ссылку после небольшой задержки, чтобы звук не обрывался при деинициализации
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.currentSound = nil
            }
        }
    }

    func playWordChanged() {
        guard Self.isEnabled else { return }
        guard let url = locateSoundURL(named: "word_changed.mp3") else { return }
        if let sound = NSSound(contentsOf: url, byReference: true) {
            sound.volume = 0.3
            self.currentSound = sound
            sound.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.currentSound = nil
            }
        }
    }

    func playSend() {
        guard Self.isEnabled else { return }
        guard let url = locateSoundURL(named: "send.mp3") else { return }
        if let sound = NSSound(contentsOf: url, byReference: true) {
            sound.volume = 0.3
            self.currentSound = sound
            sound.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.currentSound = nil
            }
        }
    }

    func playError() {
        guard Self.isEnabled else { return }
        guard let url = locateSoundURL(named: "error.mp3") else { return }
        if let sound = NSSound(contentsOf: url, byReference: true) {
            sound.volume = 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                self.currentSound = sound
                sound.play()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.currentSound = nil
                }
            }
        }
    }

    private func locateSoundURL(named fileName: String) -> URL? {
        // 1) Если звук лежит в бандле приложения в подпапке Sounds
        if let base = Bundle.main.resourceURL {
            let candidate = base.appendingPathComponent("Sounds/\(fileName)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        // 2) Относительно исполняемого файла в директории Assets/Sounds
        if let executablePath = Bundle.main.executablePath {
            let executableDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
            let candidate = executableDir.appendingPathComponent("Assets/Sounds/\(fileName)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        // 3) Абсолютный путь в репозитории (локальная разработка)
        let absolute = URL(fileURLWithPath: "/Users/sergeivaskov/Documents/Code Projects/New Punto-Punto/Assets/Sounds/\(fileName)")
        if FileManager.default.fileExists(atPath: absolute.path) {
            return absolute
        }

        return nil
    }
}


