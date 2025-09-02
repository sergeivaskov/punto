import Foundation

/// Trie node для эффективного поиска префиксов
private class TrieNode {
    var children: [Character: TrieNode] = [:]
    var isWordEnd: Bool = false
    
    func insert(_ word: String) {
        var current = self
        for char in word.lowercased() {
            if current.children[char] == nil {
                current.children[char] = TrieNode()
            }
            current = current.children[char]!
        }
        current.isWordEnd = true
    }
    
    func hasPrefix(_ prefix: String) -> Bool {
        var current = self
        for char in prefix.lowercased() {
            guard let next = current.children[char] else { return false }
            current = next
        }
        return true
    }
    
    func isCompleteWord(_ word: String) -> Bool {
        var current = self
        for char in word.lowercased() {
            guard let next = current.children[char] else { return false }
            current = next
        }
        return current.isWordEnd
    }
}

/// Менеджер словарей с быстрым поиском префиксов
public final class DictionaryManager {
    private var enTrie = TrieNode()
    private var ruTrie = TrieNode()
    private var isLoaded = false
    
    public static let shared = DictionaryManager()
    private init() {}
    
    /// Загрузка словарей при старте приложения
    public func loadDictionaries() async {
        let startTime = Date()
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                if let trie = self?.loadDictionary("en") {
                    self?.enTrie = trie
                }
            }
            group.addTask { [weak self] in
                if let trie = self?.loadDictionary("ru") {
                    self?.ruTrie = trie
                }
            }
        }
        
        isLoaded = true
        let loadTime = Date().timeIntervalSince(startTime)
        Log.d("DictionaryManager", "Dictionaries loaded in \(Int(loadTime * 1000))ms")
    }
    
    /// Загрузка отдельного словаря
    private func loadDictionary(_ language: String) -> TrieNode? {
        // Попытка найти словарь в разных местах
        let possiblePaths = [
            // 1. В bundle приложения (если добавлены как ресурсы)
            Bundle.main.path(forResource: language, ofType: "txt", inDirectory: "Sources/Dictionaries"),
            // 2. Относительно исполняемого файла (для debug builds)
            getExecutableRelativePath(language),
            // 3. Абсолютный путь (для разработки)
            "/Users/sergeivaskov/Documents/Code Projects/New Punto-Punto/Sources/Dictionaries/\(language).txt"
        ].compactMap { $0 }
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path),
               let content = try? String(contentsOfFile: path) {
                Log.d("DictionaryManager", "Loading \(language) from: \(path)")
                return createTrieFromContent(content, language: language)
            }
        }
        
        Log.d("DictionaryManager", "Failed to load \(language) dictionary from any location")
        return nil
    }
    
    private func getExecutableRelativePath(_ language: String) -> String? {
        guard let executablePath = Bundle.main.executablePath else { return nil }
        let executableDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
        return executableDir.appendingPathComponent("Sources/Dictionaries/\(language).txt").path
    }
    
    private func createTrieFromContent(_ content: String, language: String) -> TrieNode {
        let words = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.allSatisfy { $0.isLetter } }
        
        let root = TrieNode()
        for word in words {
            root.insert(word)
        }
        
        let singleCharWords = words.filter { $0.count == 1 }.count
        Log.d("DictionaryManager", "Loaded \(language.uppercased()): \(words.count) words (including \(singleCharWords) single-char)")
        return root
    }
    
    /// Поиск префикса в конкретном языке
    public func hasPrefix(_ prefix: String, in language: KeyboardLayout) -> Bool {
        guard isLoaded, prefix.count >= 2 else { return false }
        
        let trie = (language == .enUS) ? enTrie : ruTrie
        return trie.hasPrefix(prefix)
    }
    
    /// Проверка завершенного слова в конкретном языке
    public func isCompleteWord(_ word: String, in language: KeyboardLayout) -> Bool {
        guard isLoaded, !word.isEmpty else { return false }
        
        let trie = (language == .enUS) ? enTrie : ruTrie
        return trie.isCompleteWord(word)
    }
    
    /// Анализ префикса в обоих языках
    public func analyzePrefix(_ prefix: String) -> PrefixAnalysis {
        // Проверка готовности словарей (критично для первого слова)
        guard isLoaded else {
            Log.d("DictionaryManager", "⏳ DICTIONARIES NOT READY: analysis skipped for '\(prefix)'")
            return .tooShort
        }
        
        // Проверка минимальной длины
        guard prefix.count >= 3 else { return .tooShort }
        
        let hasEN = hasPrefix(prefix, in: .enUS)
        let hasRU = hasPrefix(prefix, in: .ruRU)
        
        switch (hasEN, hasRU) {
        case (true, false):
            return .onlyEnglish
        case (false, true):
            return .onlyRussian
        case (true, true):
            return .ambiguous
        case (false, false):
            return .none
        }
    }
    
    /// Анализ завершенного слова в обеих раскладках для коротких токенов
    public func analyzeCompleteWord(_ word: String) -> PrefixAnalysis {
        guard isLoaded else {
            Log.d("DictionaryManager", "⏳ DICTIONARIES NOT READY: word analysis skipped for '\(word)'")
            return .tooShort
        }
        
        guard !word.isEmpty else { return .tooShort }
        
        let hasEN = isCompleteWord(word, in: .enUS)
        let hasRU = isCompleteWord(word, in: .ruRU)
        
        switch (hasEN, hasRU) {
        case (true, false):
            return .onlyEnglish
        case (false, true):
            return .onlyRussian
        case (true, true):
            return .ambiguous
        case (false, false):
            return .none
        }
    }
}

/// Результат анализа префикса
public enum PrefixAnalysis {
    case tooShort
    case onlyEnglish
    case onlyRussian
    case ambiguous
    case none
}
