import Foundation
import Carbon

public enum KeyboardLayout: Equatable {
    case enUS
    case ruRU
}

public protocol LayoutConverter {
    func convertToken(_ token: String, from: KeyboardLayout, to: KeyboardLayout) -> String
    func convertTextPreservingNonLetters(_ text: String, from: KeyboardLayout, to: KeyboardLayout) -> String
    func detectPredominantLayout(_ text: String) -> KeyboardLayout
    func convertToOppositeLayout(_ text: String) -> String
    
    // Layout-independent keycode extraction
    func extractCharacterFromKeycode(_ keycode: CGKeyCode, layout: KeyboardLayout) -> String?
}

public final class QwertyJcukenLayoutConverter: LayoutConverter {
    // Используем строки длиной 1 для стабильного сопоставления, затем конвертируем в Character
    private let enToRu: [String: String]
    private let ruToEn: [String: String]
    
    // Keycode to character mapping for layout-independent extraction
    private let keycodeToQwerty: [CGKeyCode: String]
    private let keycodeToJcuken: [CGKeyCode: String]

    public init() {
        // Letters + punctuation by keyboard position (US QWERTY ↔ RU ЙЦУКЕН)
        self.enToRu = [
            "q":"й","w":"ц","e":"у","r":"к","t":"е","y":"н","u":"г","i":"ш","o":"щ","p":"з",
            "a":"ф","s":"ы","d":"в","f":"а","g":"п","h":"р","j":"о","k":"л","l":"д",
            "z":"я","x":"ч","c":"с","v":"м","b":"и","n":"т","m":"ь",
            // punctuation layer
            "`":"ё","~":"Ё",
            "[":"х","]":"ъ","{":"Х","}":"Ъ",
            ";":"ж",":":"Ж","'":"э","\"":"Э",
            ",":"б","<":"Б",".":"ю",">":"Ю",
            // number row (US → RU positional)
			"1":"1","!":"!",
			"2":"2","@":"\"",
			"3":"3","#":"№",
			"4":"4","$":"%",
			"5":"5","%":":",
			"6":"6","^":",",
			"7":"7","&":".",
			"8":"8","*":";",
			"9":"9","(":"(",
			"0":"0",")":")",
            "-":"-","_":"_",
            "=":"=","+":"+"
        ]

        var ruToEnMap: [String: String] = [:]
        for (en, ru) in enToRu { ruToEnMap[ru] = en }
        // Дополнительные обратные соответствия (на случай отсутствия в словаре)
        ruToEnMap["ё"] = "`"; ruToEnMap["Ё"] = "~"
        ruToEnMap["ж"] = ";"; ruToEnMap["Ж"] = ":"
        ruToEnMap["э"] = "'"; ruToEnMap["Э"] = "\""
        ruToEnMap["х"] = "["; ruToEnMap["Х"] = "{"
        ruToEnMap["ъ"] = "]"; ruToEnMap["Ъ"] = "}"
        ruToEnMap["б"] = ","; ruToEnMap["Б"] = "<"
        ruToEnMap["ю"] = "."; ruToEnMap["Ю"] = ">"
		// number row reverse (RU → EN positional)
		ruToEnMap["1"] = "1"; ruToEnMap["!"] = "!"
		ruToEnMap["2"] = "2"; ruToEnMap["\""] = "@"
		ruToEnMap["3"] = "3"; ruToEnMap["№"] = "#"
		ruToEnMap["4"] = "4"; ruToEnMap["%"] = "$"
		ruToEnMap["5"] = "5"; ruToEnMap[":"] = "%"
		ruToEnMap["6"] = "6"; ruToEnMap[","] = "^"
		ruToEnMap["7"] = "7"; ruToEnMap["."] = "&"
		ruToEnMap["8"] = "8"; ruToEnMap[";"] = "*"
		ruToEnMap["9"] = "9"; ruToEnMap["("] = "("
		ruToEnMap["0"] = "0"; ruToEnMap[")"] = ")"
        ruToEnMap["-"] = "-"; ruToEnMap["_"] = "_"
        ruToEnMap["="] = "="; ruToEnMap["+"] = "+"
        self.ruToEn = ruToEnMap
        
        // Keycode to QWERTY character mapping (layout-independent)
        self.keycodeToQwerty = [
            // Letter row 1 (top)
            CGKeyCode(kVK_ANSI_Q): "q", CGKeyCode(kVK_ANSI_W): "w", CGKeyCode(kVK_ANSI_E): "e", CGKeyCode(kVK_ANSI_R): "r", CGKeyCode(kVK_ANSI_T): "t",
            CGKeyCode(kVK_ANSI_Y): "y", CGKeyCode(kVK_ANSI_U): "u", CGKeyCode(kVK_ANSI_I): "i", CGKeyCode(kVK_ANSI_O): "o", CGKeyCode(kVK_ANSI_P): "p",
            // Letter row 2 (middle)  
            CGKeyCode(kVK_ANSI_A): "a", CGKeyCode(kVK_ANSI_S): "s", CGKeyCode(kVK_ANSI_D): "d", CGKeyCode(kVK_ANSI_F): "f", CGKeyCode(kVK_ANSI_G): "g",
            CGKeyCode(kVK_ANSI_H): "h", CGKeyCode(kVK_ANSI_J): "j", CGKeyCode(kVK_ANSI_K): "k", CGKeyCode(kVK_ANSI_L): "l",
            // Letter row 3 (bottom)
            CGKeyCode(kVK_ANSI_Z): "z", CGKeyCode(kVK_ANSI_X): "x", CGKeyCode(kVK_ANSI_C): "c", CGKeyCode(kVK_ANSI_V): "v", CGKeyCode(kVK_ANSI_B): "b",
            CGKeyCode(kVK_ANSI_N): "n", CGKeyCode(kVK_ANSI_M): "m",
            // Numbers
            CGKeyCode(kVK_ANSI_1): "1", CGKeyCode(kVK_ANSI_2): "2", CGKeyCode(kVK_ANSI_3): "3", CGKeyCode(kVK_ANSI_4): "4", CGKeyCode(kVK_ANSI_5): "5",
            CGKeyCode(kVK_ANSI_6): "6", CGKeyCode(kVK_ANSI_7): "7", CGKeyCode(kVK_ANSI_8): "8", CGKeyCode(kVK_ANSI_9): "9", CGKeyCode(kVK_ANSI_0): "0",
            // Punctuation
            CGKeyCode(kVK_ANSI_Grave): "`", CGKeyCode(kVK_ANSI_Minus): "-", CGKeyCode(kVK_ANSI_Equal): "=",
            CGKeyCode(kVK_ANSI_LeftBracket): "[", CGKeyCode(kVK_ANSI_RightBracket): "]", CGKeyCode(kVK_ANSI_Backslash): "\\",
            CGKeyCode(kVK_ANSI_Semicolon): ";", CGKeyCode(kVK_ANSI_Quote): "'",
            CGKeyCode(kVK_ANSI_Comma): ",", CGKeyCode(kVK_ANSI_Period): ".", CGKeyCode(kVK_ANSI_Slash): "/"
        ]
        
        // Keycode to JCUKEN character mapping (layout-independent)
        var keycodeToJcukenMap: [CGKeyCode: String] = [:]
        for (keycode, qwertyChar) in keycodeToQwerty {
            if let jcukenChar = enToRu[qwertyChar] {
                keycodeToJcukenMap[keycode] = jcukenChar
            } else {
                keycodeToJcukenMap[keycode] = qwertyChar // fallback
            }
        }
        self.keycodeToJcuken = keycodeToJcukenMap
    }

    public func convertToken(_ token: String, from: KeyboardLayout, to: KeyboardLayout) -> String {
        guard from != to else { return token }
        // Detect word casing style: lower, UPPER, Title
        let style = CasingStyle.detect(in: token)
        let lower = token.lowercased()
        let mappedLower = mapLetters(lower, from: from, to: to)
        // Если входной токен не содержит букв, регистр к результату не применяем.
        // Это предотвращает ложный подъём регистра при конверсии символов (например, "]" → "Ъ").
        let containsLetters = token.contains { $0.isLetter }
        if !containsLetters {
            return mappedLower
        }
        // Если исходный токен был ПРОПИСНЫМ, а результат — одиночный символ, у которого есть shifted-пара на EN, вернём shifted-вариант.
        // Это сохраняет «верхний регистр» через символический этап (например, "Ъ" → "}" вместо "]").
        if style == .upper, mappedLower.count == 1, let c = mappedLower.first {
            let enShiftPairs: [Character: Character] = [
                "]": "}", "[": "{",
                ";": ":", "'": "\"",
                ",": "<", ".": ">",
                "`": "~"
            ]
            if let shifted = enShiftPairs[c] {
                return String(shifted)
            }
        }
        return style.apply(on: mappedLower)
    }

    public func convertTextPreservingNonLetters(_ text: String, from: KeyboardLayout, to: KeyboardLayout) -> String {
        guard from != to else { return text }
        // Split into word and non-word sequences to preserve casing semantics on per-token basis
        var result = ""
        var current = ""
        var isWord = false
        for ch in text {
            if ch.isLetter {
                if !isWord { result.append(current); current = ""; isWord = true }
                current.append(ch)
            } else {
                if isWord {
                    result.append(convertToken(current, from: from, to: to))
                    current = ""
                }
                isWord = false
                // Map punctuation and other non-letter characters positionally as well
                current.append(mapNonLetter(ch, from: from, to: to))
            }
        }
        if isWord {
            result.append(convertToken(current, from: from, to: to))
        } else {
            result.append(current)
        }
        return result
    }

    private func mapLetters(_ text: String, from: KeyboardLayout, to: KeyboardLayout) -> String {
        switch (from, to) {
        case (.enUS, .ruRU):
            return String(text.map { mapChar($0, table: enToRu) })
        case (.ruRU, .enUS):
            return String(text.map { mapChar($0, table: ruToEn) })
        default:
            return text
        }
    }

    private func mapChar(_ ch: Character, table: [String: String]) -> Character {
        let key = String(ch)
        if let mapped = table[key], let m = mapped.first { return m }
        return ch
    }

    private func mapNonLetter(_ ch: Character, from: KeyboardLayout, to: KeyboardLayout) -> Character {
        switch (from, to) {
        case (.enUS, .ruRU): return mapChar(ch, table: enToRu)
        case (.ruRU, .enUS): return mapChar(ch, table: ruToEn)
        default: return ch
        }
    }
    
    public func detectPredominantLayout(_ text: String) -> KeyboardLayout {
        var enCount = 0
        var ruCount = 0
        
        for char in text {
            let charString = String(char)
            if char.isLetter {
                if enToRu[charString.lowercased()] != nil {
                    enCount += 1
                } else if ruToEn[charString.lowercased()] != nil {
                    ruCount += 1
                }
            } else {
                // Check special characters and punctuation using mapping tables
                if enToRu[charString] != nil {
                    enCount += 1
                } else if ruToEn[charString] != nil {
                    ruCount += 1
                }
            }
        }
        
        // Если равное количество или больше русских - предпочитаем русскую раскладку
        return enCount > ruCount ? .enUS : .ruRU
    }
    
    public func convertToOppositeLayout(_ text: String) -> String {
        let predominantLayout = detectPredominantLayout(text)
        let targetLayout: KeyboardLayout = (predominantLayout == .enUS) ? .ruRU : .enUS
        return convertTextPreservingNonLetters(text, from: predominantLayout, to: targetLayout)
    }
    
    /// Layout-independent character extraction from raw keycode
    public func extractCharacterFromKeycode(_ keycode: CGKeyCode, layout: KeyboardLayout) -> String? {
        switch layout {
        case .enUS:
            return keycodeToQwerty[keycode]
        case .ruRU:
            return keycodeToJcuken[keycode]
        }
    }
}

enum CasingStyle {
    case lower
    case upper
    case title
    case mixed

    static func detect(in token: String) -> CasingStyle {
        guard !token.isEmpty else { return .lower }
        if token == token.uppercased() { return .upper }
        if token == token.lowercased() { return .lower }
        let first = token.prefix(1)
        let rest = token.dropFirst()
        if first == first.uppercased() && rest == rest.lowercased() { return .title }
        return .mixed
    }

    func apply(on lowerMapped: String) -> String {
        switch self {
        case .lower: return lowerMapped
        case .upper: return lowerMapped.uppercased()
        case .title:
            guard let first = lowerMapped.first else { return lowerMapped }
            return String(first).uppercased() + lowerMapped.dropFirst()
        case .mixed:
            // Best effort: keep as lower (safer than corrupting); caller may refine per-character case if needed
            return lowerMapped
        }
    }
}



