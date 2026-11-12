import Cocoa
import Carbon

// MARK: - Constants & Types

private let SELF_EVENT_TAG: Int64 = 0x4B4F_454E // "KOEN"

/// What the user taught the app about one English keystroke string.
enum LearnedEnToKo: Equatable {
    /// Shift+Space turned this English string into Korean. Space may do it next time.
    case accept
    /// Space turned it into Korean and the user immediately deleted that insertion.
    case reject
}

enum AutoConvertMode: String, CaseIterable {
    case conservative = "conservative"
    case aggressive   = "aggressive"
    case manualOnly   = "manual"

    var title: String {
        switch self {
        case .conservative: return "보수적 자동 변환 (자모 깨짐 + 명령어)"
        case .aggressive:   return "적극적 자동 변환 (일반 한↔영 오타 포함)"
        case .manualOnly:   return "수동 변환 전용 (Shift + Space만 사용)"
        }
    }
}

struct KeyStroke: Equatable {
    let keyCode: CGKeyCode
    let isShift: Bool
    let enChar: Character
    let koJamo: Character
}

struct SimulationResult: Equatable {
    let englishText: String
    let koreanText: String
    let committedScalars: [Character]
    let composingStrokes: [KeyStroke]
    let composingText: String

    /// Total backspaces required when deleting an active word in Korean (2SetKorean) mode
    /// BEFORE Space has committed the composing syllable:
    /// - `composingStrokes.count` backspaces are absorbed by KoreanIM to undo the uncommitted `markedText`
    /// - `committedScalars.count` backspaces delete the already-committed characters
    var backspacesInKoreanComposing: Int {
        return composingStrokes.count + committedScalars.count
    }

    /// Total backspaces required when deleting a Korean word AFTER Space has already committed it
    /// (excluding the trailing space itself):
    var committedKoreanCharCount: Int {
        return koreanText.count
    }

    /// Total backspaces required when deleting an active word in English (ABC) mode:
    var backspacesInEnglish: Int {
        return englishText.count
    }
}

// MARK: - Dubeolsik (2-Set Korean) Automata

enum HangulAutomata {
    // ANSI KeyCode -> (lowercase en, uppercase en, unshifted ko, shifted ko)
    static let keyMap: [CGKeyCode: (Character, Character, Character, Character)] = [
        0:  ("a", "A", "ㅁ", "ㅁ"),
        1:  ("s", "S", "ㄴ", "ㄴ"),
        2:  ("d", "D", "ㅇ", "ㅇ"),
        3:  ("f", "F", "ㄹ", "ㄹ"),
        4:  ("h", "H", "ㅗ", "ㅗ"),
        5:  ("g", "G", "ㅎ", "ㅎ"),
        6:  ("z", "Z", "ㅋ", "ㅋ"),
        7:  ("x", "X", "ㅌ", "ㅌ"),
        8:  ("c", "C", "ㅊ", "ㅊ"),
        9:  ("v", "V", "ㅍ", "ㅍ"),
        11: ("b", "B", "ㅠ", "ㅠ"),
        12: ("q", "Q", "ㅂ", "ㅃ"),
        13: ("w", "W", "ㅈ", "ㅉ"),
        14: ("e", "E", "ㄷ", "ㄸ"),
        15: ("r", "R", "ㄱ", "ㄲ"),
        16: ("y", "Y", "ㅛ", "ㅛ"),
        17: ("t", "T", "ㅅ", "ㅆ"),
        31: ("o", "O", "ㅐ", "ㅒ"),
        32: ("u", "U", "ㅕ", "ㅕ"),
        34: ("i", "I", "ㅑ", "ㅑ"),
        35: ("p", "P", "ㅔ", "ㅖ"),
        37: ("l", "L", "ㅣ", "ㅣ"),
        38: ("j", "J", "ㅓ", "ㅓ"),
        40: ("k", "K", "ㅏ", "ㅏ"),
        45: ("n", "N", "ㅜ", "ㅜ"),
        46: ("m", "M", "ㅡ", "ㅡ"),
    ]

    static let charToKeyStroke: [Character: KeyStroke] = {
        var dict: [Character: KeyStroke] = [:]
        for (code, (lo, hi, ko, koShift)) in keyMap {
            dict[lo] = KeyStroke(keyCode: code, isShift: false, enChar: lo, koJamo: ko)
            dict[hi] = KeyStroke(keyCode: code, isShift: true,  enChar: hi, koJamo: koShift)
        }
        return dict
    }()

    static func makeStroke(keyCode: CGKeyCode, isShift: Bool) -> KeyStroke? {
        guard let entry = keyMap[keyCode] else { return nil }
        return KeyStroke(
            keyCode: keyCode,
            isShift: isShift,
            enChar: isShift ? entry.1 : entry.0,
            koJamo: isShift ? entry.3 : entry.2
        )
    }

    static func strokes(fromEnglish text: String) -> [KeyStroke]? {
        var result: [KeyStroke] = []
        for ch in text {
            guard let s = charToKeyStroke[ch] else { return nil }
            result.append(s)
        }
        return result
    }

    private static let choseongs: [Character] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]

    private static let jungseongs: [Character] = [
        "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ",
        "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ"
    ]

    private static let jongseongs: [Character] = [
        "\0", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ",
        "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]

    private static let choseongMap: [Character: Int] = {
        var m: [Character: Int] = [:]
        for (i, c) in choseongs.enumerated() { m[c] = i }
        return m
    }()

    private static let jungseongMap: [Character: Int] = {
        var m: [Character: Int] = [:]
        for (i, c) in jungseongs.enumerated() { m[c] = i }
        return m
    }()

    private static let jongseongMap: [Character: Int] = {
        var m: [Character: Int] = [:]
        for (i, c) in jongseongs.enumerated() where i > 0 { m[c] = i }
        return m
    }()

    // Compound vowels: (firstJungIdx, secondJungIdx) -> combinedJungIdx
    private static func combineJungseong(_ first: Int, _ second: Int) -> Int? {
        switch (first, second) {
        case (8, 0):  return 9  // ㅗ + ㅏ = ㅘ
        case (8, 1):  return 10 // ㅗ + ㅐ = ㅙ
        case (8, 20): return 11 // ㅗ + ㅣ = ㅚ
        case (13, 4): return 14 // ㅜ + ㅓ = ㅝ
        case (13, 5): return 15 // ㅜ + ㅔ = ㅞ
        case (13, 20): return 16 // ㅜ + ㅣ = ㅟ
        case (18, 20): return 19 // ㅡ + ㅣ = ㅢ
        default: return nil
        }
    }

    // Compound jongseongs: (firstJongIdx, nextConsonantJamo) -> combinedJongIdx
    private static func combineJongseong(_ firstJong: Int, _ nextConsonant: Character) -> Int? {
        switch (firstJong, nextConsonant) {
        case (1, "ㅅ"):  return 3  // ㄱ + ㅅ = ㄳ
        case (4, "ㅈ"):  return 5  // ㄴ + ㅈ = ㄵ
        case (4, "ㅎ"):  return 6  // ㄴ + ㅎ = ㄶ
        case (8, "ㄱ"):  return 9  // ㄹ + ㄱ = ㄺ
        case (8, "ㅁ"):  return 10 // ㄹ + ㅁ = ㄻ
        case (8, "ㅂ"):  return 11 // ㄹ + ㅂ = ㄼ
        case (8, "ㅅ"):  return 12 // ㄹ + ㅅ = ㄽ
        case (8, "ㅌ"):  return 13 // ㄹ + ㅌ = ㄾ
        case (8, "ㅍ"):  return 14 // ㄹ + ㅍ = ㄿ
        case (8, "ㅎ"):  return 15 // ㄹ + ㅎ = ㅀ
        case (17, "ㅅ"): return 18 // ㅂ + ㅅ = ㅄ
        default: return nil
        }
    }

    // Split jongseong when a vowel follows: returns (remainingJongIdx?, movedChoseongIdx)
    private static func splitJongseong(_ jong: Int) -> (Int?, Int) {
        switch jong {
        case 3:  return (1, choseongMap["ㅅ"]!)  // ㄳ -> ㄱ, ㅅ
        case 5:  return (4, choseongMap["ㅈ"]!)  // ㄵ -> ㄴ, ㅈ
        case 6:  return (4, choseongMap["ㅎ"]!)  // ㄶ -> ㄴ, ㅎ
        case 9:  return (8, choseongMap["ㄱ"]!)  // ㄺ -> ㄹ, ㄱ
        case 10: return (8, choseongMap["ㅁ"]!)  // ㄻ -> ㄹ, ㅁ
        case 11: return (8, choseongMap["ㅂ"]!)  // ㄼ -> ㄹ, ㅂ
        case 12: return (8, choseongMap["ㅅ"]!)  // ㄽ -> ㄹ, ㅅ
        case 13: return (8, choseongMap["ㅌ"]!)  // ㄾ -> ㄹ, ㅌ
        case 14: return (8, choseongMap["ㅍ"]!)  // ㄿ -> ㄹ, ㅍ
        case 15: return (8, choseongMap["ㅎ"]!)  // ㅀ -> ㄹ, ㅎ
        case 18: return (17, choseongMap["ㅅ"]!) // ㅄ -> ㅂ, ㅅ
        default:
            let ch = jongseongs[jong]
            return (nil, choseongMap[ch]!)
        }
    }

    private static func renderSyllable(cho: Int?, jung: Int?, jong: Int?) -> Character? {
        if let c = cho, let v = jung {
            let j = jong ?? 0
            let code = 0xAC00 + (c * 21 * 28) + (v * 28) + j
            return Character(UnicodeScalar(code)!)
        } else if let c = cho {
            return choseongs[c]
        } else if let v = jung {
            return jungseongs[v]
        }
        return nil
    }

    /// Simulates exact macOS 2SetKorean composition on a sequence of keystrokes.
    static func simulate(_ strokes: [KeyStroke]) -> SimulationResult {
        var committedChars: [Character] = []
        var cho: Int? = nil
        var jung: Int? = nil
        var jong: Int? = nil
        var compStrokes: [KeyStroke] = []

        func flushComposing() {
            if let ch = renderSyllable(cho: cho, jung: jung, jong: jong) {
                committedChars.append(ch)
            }
            cho = nil
            jung = nil
            jong = nil
            compStrokes.removeAll()
        }

        for stroke in strokes {
            let jamo = stroke.koJamo
            if let cIdx = choseongMap[jamo] {
                // Consonant input
                if cho == nil && jung == nil {
                    cho = cIdx
                    compStrokes = [stroke]
                } else if cho != nil && jung == nil {
                    flushComposing()
                    cho = cIdx
                    compStrokes = [stroke]
                } else if cho == nil && jung != nil {
                    flushComposing()
                    cho = cIdx
                    compStrokes = [stroke]
                } else if cho != nil && jung != nil && jong == nil {
                    if let jIdx = jongseongMap[jamo] {
                        jong = jIdx
                        compStrokes.append(stroke)
                    } else {
                        // ㄸ, ㅃ, ㅉ cannot be jongseong
                        flushComposing()
                        cho = cIdx
                        compStrokes = [stroke]
                    }
                } else if let curJong = jong {
                    if let combined = combineJongseong(curJong, jamo) {
                        jong = combined
                        compStrokes.append(stroke)
                    } else {
                        flushComposing()
                        cho = cIdx
                        compStrokes = [stroke]
                    }
                }
            } else if let vIdx = jungseongMap[jamo] {
                // Vowel input
                if cho == nil && jung == nil {
                    jung = vIdx
                    compStrokes = [stroke]
                } else if cho != nil && jung == nil {
                    jung = vIdx
                    compStrokes.append(stroke)
                } else if cho == nil, let curJung = jung {
                    if let combined = combineJungseong(curJung, vIdx) {
                        jung = combined
                        compStrokes.append(stroke)
                    } else {
                        flushComposing()
                        jung = vIdx
                        compStrokes = [stroke]
                    }
                } else if cho != nil, let curJung = jung, jong == nil {
                    if let combined = combineJungseong(curJung, vIdx) {
                        jung = combined
                        compStrokes.append(stroke)
                    } else {
                        flushComposing()
                        jung = vIdx
                        compStrokes = [stroke]
                    }
                } else if let curCho = cho, let curJung = jung, let curJong = jong {
                    // Jongseong split (연음)
                    let (remainJong, nextCho) = splitJongseong(curJong)
                    let movedStroke = compStrokes.removeLast()
                    if let committedCh = renderSyllable(cho: curCho, jung: curJung, jong: remainJong) {
                        committedChars.append(committedCh)
                    }
                    cho = nextCho
                    jung = vIdx
                    jong = nil
                    compStrokes = [movedStroke, stroke]
                }
            }
        }

        let enText = String(strokes.map { $0.enChar })
        let compChar = renderSyllable(cho: cho, jung: jung, jong: jong)
        let compText = compChar.map { String($0) } ?? ""
        let koText = String(committedChars) + compText

        return SimulationResult(
            englishText: enText,
            koreanText: koText,
            committedScalars: committedChars,
            composingStrokes: compStrokes,
            composingText: compText
        )
    }

    static func containsStandaloneJamo(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Hangul Compatibility Jamo: U+3131 (ㄱ) ... U+3163 (ㅣ)
            if scalar.value >= 0x3131 && scalar.value <= 0x3163 {
                return true
            }
        }
        return false
    }

    static func isAllCompleteSyllables(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        for scalar in text.unicodeScalars {
            if scalar.value < 0xAC00 || scalar.value > 0xD7A3 {
                return false
            }
        }
        return true
    }
}

// MARK: - Word Buffer (Handles Mid-Word Backspace Accurately)

final class WordBuffer {
    /// Committed character stroke groups (already committed via insertText in Korean mode)
    private(set) var committedGroups: [[KeyStroke]] = []
    /// Currently composing strokes (in markedText in Korean mode)
    private(set) var composingStrokes: [KeyStroke] = []

    var allStrokes: [KeyStroke] {
        return committedGroups.flatMap { $0 } + composingStrokes
    }

    var isEmpty: Bool {
        return committedGroups.isEmpty && composingStrokes.isEmpty
    }

    func reset() {
        committedGroups.removeAll()
        composingStrokes.removeAll()
    }

    func append(_ stroke: KeyStroke, inKoreanMode: Bool) {
        if !inKoreanMode {
            composingStrokes.append(stroke)
            return
        }
        // Replay `composingStrokes + [stroke]` through HangulAutomata to see if a syllable committed
        let prevCount = composingStrokes.count
        let testStrokes = composingStrokes + [stroke]
        let sim = HangulAutomata.simulate(testStrokes)
        if sim.committedScalars.isEmpty {
            composingStrokes = sim.composingStrokes
        } else {
            // The prefix before `sim.composingStrokes` was committed as a single character
            let committedStrokeCount = (prevCount + 1) - sim.composingStrokes.count
            if committedStrokeCount > 0 {
                let committedGroup = Array(testStrokes.prefix(committedStrokeCount))
                committedGroups.append(committedGroup)
            }
            composingStrokes = sim.composingStrokes
        }
    }

    /// Models a single Backspace press by the user so our buffer stays 100% in sync with macOS
    func handleUserBackspace(inKoreanMode: Bool) {
        if !inKoreanMode {
            if !composingStrokes.isEmpty {
                composingStrokes.removeLast()
            } else if !committedGroups.isEmpty {
                var last = committedGroups.removeLast()
                last.removeLast()
                if !last.isEmpty {
                    committedGroups.append(last)
                }
            }
            return
        }
        // In Korean mode:
        // - If composingStrokes is non-empty, 1 Backspace removes 1 jamo stroke from composingStrokes
        // - If composingStrokes is empty, 1 Backspace deletes the entire last committed syllable group!
        if !composingStrokes.isEmpty {
            composingStrokes.removeLast()
        } else if !committedGroups.isEmpty {
            committedGroups.removeLast()
        }
    }

    func snapshot() -> SimulationResult {
        let strokes = allStrokes
        let enText = String(strokes.map { $0.enChar })
        var committedChars: [Character] = []
        for group in committedGroups {
            let groupSim = HangulAutomata.simulate(group)
            for ch in groupSim.koreanText {
                committedChars.append(ch)
            }
        }
        let compSim = HangulAutomata.simulate(composingStrokes)
        let koText = String(committedChars) + compSim.koreanText
        return SimulationResult(
            englishText: enText,
            koreanText: koText,
            committedScalars: committedChars,
            composingStrokes: composingStrokes,
            composingText: compSim.koreanText
        )
    }
}

// MARK: - Typo Detection Heuristics

enum TypoDetector {
    /// Intentional Korean initialisms (초성어) and emoticons that contain standalone jamos
    /// and must NEVER be auto-converted to English.
    static let koreanJamoAllowlist: Set<String> = [
        "ㄱㅅ", "ㅈㅅ", "ㅅㄱ", "ㅊㅋ", "ㅇㅋ", "ㅎㅇ", "ㅂㅇ", "ㅇㅈ", "ㄹㅇ",
        "ㅁㅈ", "ㅈㅂ", "ㄱㅊ", "ㅇㅎ", "ㅎㄷㄷ", "ㅂㅂ", "ㄱㄷ", "ㄴㄴ", "ㅇㅇ",
        "ㄷㄷ", "ㄱㄱ", "ㅅㅅ", "ㅉㅉ", "ㅡㅡ", "ㅋ", "ㅎ", "ㅠ", "ㅜ", "ㅇ",
        "ㄱㅅㅎㄴㄷ", "ㅊㅋㅊㅋ", "ㅅㄱㅇ", "ㅎㅇㅌ", "ㅇㅈ?"
    ]

    /// English commands/tokens whose Dubeolsik keystrokes happen to compose into complete Hangul syllables
    /// without standalone jamos, AND whose composed Hangul is NOT a normal standalone Korean word.
    /// (e.g. git -> 햣, curl -> 처기, sudo -> 녀애, vi -> 퍄, zig -> ㅋ깋)
    static let safeComposedCommandAllowlist: Set<String> = [
        "git", "curl", "sudo", "vi", "vim", "nvim", "tmux", "ssh", "scp",
        "ls", "cd", "cp", "mv", "rm", "ln", "df", "du", "ps", "jq", "gh",
        "rg", "fd", "bat", "cat", "awk", "sed", "tar", "zip", "top", "htop",
        "brew", "npm", "npx", "pnpm", "yarn", "bun", "pip", "uv", "cargo",
        "rustc", "go", // Note: `go` -> `해` is filtered out below in `ambiguousKoreanWords`
        "python", "python3", "node", "deno", "claude", "cursor", "code",
        "docker", "kubectl", "helm", "terraform", "make", "cmake", "ninja",
        "chmod", "chown", "mkdir", "rmdir", "touch", "find", "grep", "egrep",
        "less", "head", "tail", "echo", "export", "source", "alias", "which",
        "whereis", "open", "clear", "exit", "kill", "pkill", "killall",
        "status", "commit", "checkout", "branch", "merge", "rebase", "stash",
        "push", "pull", "fetch", "clone", "diff", "log", "init", "add", "reset"
    ]

    /// Real Korean words that happen to match short English words on Dubeolsik.
    /// Conservative mode never auto-converts these on Space. Shift+Space also
    /// leaves them alone: every scalar is a finished syllable.
    static let ambiguousKoreanWords: Set<String> = [
        "해", // go
        "애", // do
        "내", // so
        "새", // to
        "무", // an
        "마", // am
        "호", // gh
        "오", // dh
        "우", // dn
        "아", // dk
        "야", // di
        "어", // dj
        "여", // du
        "이", // dl
        "그", // rm
        "나", // sk
        "너", // sj
        "더", // ej
        "다", // ek
        "자", // wk
        "차", // ck
        "코", // zh
        "키", // zl
        "피", // vl
        "비", // ql
        "시", // tl
        "미", // al
        "리", // fl
        "기", // rl
    ]

    /// Valid vowelless English CLI commands / dev tokens
    static let vowellessEnglishTokens: Set<String> = [
        "ls", "cd", "cp", "mv", "rm", "ln", "df", "ps", "jq", "gh", "rg", "fd",
        "sh", "wc", "nc", "id", "ip", "xz", "ssh", "zsh", "npm", "npx", "nvm",
        "pnpm", "pwd", "pkg", "src", "cfg", "tmp", "var", "bin", "lib", "dev",
        "srv", "mnt", "sys", "mkdir", "rmdir", "chmod", "chown", "chgrp",
        "ctrl", "cmd", "str", "ptr", "len", "idx", "msg", "ctx", "req", "res",
        "arg", "args", "fn", "impl", "std", "fmt", "sql", "jwt", "xml", "yml",
        "csv", "tsv", "png", "jpg", "svg", "pdf", "gif", "mp3", "mp4", "mkv",
        "ttf", "tgz", "bz2", "zst", "llm", "gpt", "mcp", "nvim", "tmux", "htop",
        "wq", "qa", "vs", "sp", "bd", "bn", "bp", "rf", "la", "al", "ll"
    ]

    /// Vim command-line tokens right after `:` (e.g. `:ㅂ` -> `:q`, `:ㅈㅂ` -> `:wq`)
    static let vimColonCommands: Set<String> = [
        "q", "w", "wq", "wa", "qa", "wqa", "x", "e", "vs", "sp", "bd", "bn", "bp", "noh", "set"
    ]

    /// Common English words/roots that happen to compose into Hangul syllables without standalone jamos
    /// (to avoid false-positive English -> Korean conversion in Aggressive mode).
    static let englishWordSafelist: Set<String> = [
        "rudy", "duke", "judo", "silo", "kilo", "fifo", "lifo", "todo", "logo",
        "soho", "momo", "polo", "solo", "yolo", "dodo", "coco", "bobo", "jojo",
        "hoho", "lolo", "nono", "popo", "roro", "toto", "zozo", "mini", "midi",
        "wiki", "tiki", "kiwi", "fiji", "siri", "bibi", "didi", "gigi", "lili",
        "mimi", "nini", "pipi", "riri", "sisi", "titi", "vivi", "zizi", "java",
        "django", "djvu", "vuejs",
        "data", "nasa", "sara", "tara", "lara", "mara", "nara", "para", "zara",
        "baba", "dada", "gaga", "haha", "kaka", "lala", "mama", "nana", "papa",
        "tata", "vava", "zaza", "koko", "fofo", "gogo", "milk", "silk", "bulk",
        "hulk", "sulk", "folk", "yolk", "talk", "walk", "balk", "caulk", "golf",
        "wolf", "gulf", "self", "half", "calf", "held", "weld", "meld", "geld",
        "gold", "cold", "bold", "fold", "hold", "mold", "sold", "told", "wild",
        "mild", "gild", "build", "guild", "child", "film", "helm", "palm", "calm",
        "balm", "psalm", "help", "kelp", "yelp", "gulp", "pulp", "bulb", "cult",
        "jolt", "bolt", "colt", "molt", "volt", "belt", "felt", "melt", "pelt",
        "hilt", "jilt", "kilt", "lilt", "milt", "silt", "tilt", "wilt", "salt",
        "malt", "halt", "fork", "pork", "cork", "work", "york", "dark", "bark",
        "mark", "park", "lark", "shark", "spark", "stark", "jerk", "perk", "clerk",
        "dirk", "kirk", "smirk", "quirk", "turk", "lurk", "murk", "form", "worm",
        "norm", "term", "germ", "perm", "firm", "farm", "harm", "warm", "charm",
        "alarm", "swarm", "born", "corn", "horn", "morn", "porn", "torn", "worn",
        "burn", "turn", "fern", "kern", "stern", "barn", "darn", "yarn", "warn",
        "bird", "gird", "word", "lord", "cord", "ford", "sword", "curd", "nerd",
        "herd", "hard", "card", "yard", "ward", "guard", "board", "hoard", "girl",
        "curl", "hurl", "furl", "purl", "swirl", "twirl", "whirl", "earl", "pearl",
        "marl", "snarl", "gnarl", "carp", "harp", "tarp", "warp", "sharp", "scarp",
        "corp", "chirp", "slurp", "usurp", "cart", "dart", "fart", "hart", "mart",
        "part", "tart", "chart", "smart", "start", "quart", "dirt", "flirt", "shirt",
        "skirt", "squirt", "fort", "port", "sort", "tort", "short", "snort", "sport",
        "hurt", "curt", "blurt", "spurt", "yurt", "verb", "herb", "curb", "blurb",
        "garb", "barb", "orb", "serf", "turf", "surf", "scurf", "scarf", "dwarf",
        "wharf", "erg", "berg", "burg", "borg",
        "dharmsala"
    ]

    static func isIntentionalKoreanJamo(_ koText: String) -> Bool {
        if koreanJamoAllowlist.contains(koText) { return true }
        let scalars = Array(koText)
        guard !scalars.isEmpty else { return true }
        // Single repeated jamo: ㅋㅋㅋ, ㅎㅎㅎ, ㅠㅠ, ㅜㅜ, ㅇㅇ, ㄱㄱ, etc.
        if Set(scalars).count == 1 { return true }
        // Combination of only laughing/crying/ack jamos: ㅋ, ㅎ, ㅠ, ㅜ, ㅇ
        let emotiveSet: Set<Character> = ["ㅋ", "ㅎ", "ㅠ", "ㅜ", "ㅇ"]
        if scalars.allSatisfy({ emotiveSet.contains($0) }) { return true }
        return false
    }

    static func isPlausibleEnglishToken(_ enText: String) -> Bool {
        let lower = enText.lowercased()
        guard lower.count >= 2 else { return false }
        if vowellessEnglishTokens.contains(lower) || safeComposedCommandAllowlist.contains(lower) {
            return true
        }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        return lower.contains(where: { vowels.contains($0) })
    }

    /// Evaluates whether a word typed while in Korean mode (`2SetKorean`) should be auto-converted to English.
    static func shouldAutoConvertKoToEn(
        sim: SimulationResult,
        mode: AutoConvertMode,
        prefixSymbol: Character? = nil
    ) -> Bool {
        guard mode != .manualOnly else { return false }
        let enLower = sim.englishText.lowercased()
        let koText = sim.koreanText

        // Vim command-line mode right after ':' (e.g. :ㅂ -> :q, :ㅈㅂ -> :wq, :ㅈ -> :w)
        if prefixSymbol == ":" && vimColonCommands.contains(enLower) {
            return true
        }

        // CLI short flags right after '-' (e.g. -ㅣㅁ -> -la, -ㄱㄹ -> -rf)
        if prefixSymbol == "-" && enLower.count >= 1 && HangulAutomata.containsStandaloneJamo(koText) {
            return true
        }

        guard enLower.count >= 2 else { return false }

        // Never auto-convert real ambiguous Korean words (like 해, 내, 애) in Conservative mode
        if ambiguousKoreanWords.contains(koText) {
            return false
        }

        // 1. Explicit safe command allowlist (e.g., git -> 햣, curl -> 쳐기, sudo -> 녀애, vi -> 퍄)
        if safeComposedCommandAllowlist.contains(enLower) {
            return true
        }

        // 2. Broken / standalone jamo detection (e.g., ㅅㅡㅕㅌ -> tmux, ㅣㄴ -> ls, 치명ㄷ -> claude)
        if HangulAutomata.containsStandaloneJamo(koText) {
            if prefixSymbol == nil && isIntentionalKoreanJamo(koText) {
                return false
            }
            return isPlausibleEnglishToken(sim.englishText)
        }

        return false
    }

    /// Shift+Space Korean → English. A finished composition (every scalar in
    /// AC00–D7A3, e.g. 안녕, 해) stays Korean. Broken compatibility jamo
    /// (스ㅕㅌ, ㅣㄴ, 치명ㄷ) still converts.
    static func shouldManualConvertKoToEn(sim: SimulationResult) -> Bool {
        return !HangulAutomata.isAllCompleteSyllables(sim.koreanText)
    }

    /// Evaluates whether a word typed while in English mode (`ABC`) should be auto-converted to Korean.
    static func shouldAutoConvertEnToKo(
        sim: SimulationResult,
        mode: AutoConvertMode,
        learned: LearnedEnToKo? = nil
    ) -> Bool {
        // Only active in Aggressive mode (in Conservative mode, user converts En->Ko with Shift+Space)
        guard mode == .aggressive else { return false }
        // A correction the user already made outranks the heuristic.
        if learned == .reject { return false }
        if learned == .accept { return !sim.koreanText.isEmpty }
        let en = sim.englishText
        let ko = sim.koreanText

        // Require at least 4 keystrokes (at least ~2 Korean syllables like "dkssud" -> "안녕")
        guard en.count >= 4 else { return false }
        // Avoid converting camelCase / PascalCase / ACRONYMS unless Shift was only used for valid Korean twin consonants (ㅃㅉㄸㄲㅆㅒㅖ)
        let validShiftedEn: Set<Character> = ["Q", "W", "E", "R", "T", "O", "P"]
        for ch in en where ch.isUppercase {
            if !validShiftedEn.contains(ch) { return false }
        }

        let lower = en.lowercased()
        if safeComposedCommandAllowlist.contains(lower) ||
           vowellessEnglishTokens.contains(lower) ||
           englishWordSafelist.contains(lower) {
            return false
        }

        // Must compose into 100% complete Hangul syllables (no standalone broken jamos!)
        guard HangulAutomata.isAllCompleteSyllables(ko), ko.count >= 2 else {
            return false
        }

        // Check if the English string looks unnatural as English (e.g., Dubeolsik vowel keys k,j,h,n,m,l,u,i,y,p
        // used where English expects a,e,i,o,u, or unpronounceable consonant clusters like "dkss", "gksr", "qksr")
        let englishVowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        let vowelCount = lower.filter { englishVowels.contains($0) }.count
        if vowelCount == 0 {
            return true // 0 English vowels yet forms >= 2 complete Korean syllables (e.g. "gksrmf" -> "한글")!
        }

        // Detect impossible English bigrams/trigrams that frequently occur in Dubeolsik Korean typing
        let dubeolsikPatterns = [
            "dkss", "gksr", "qksr", "tmqs", "slek", "tngk", "wkrd", "ehdw",
            "rmff", "chlw", "rudg", "tjsx", "dbtj", "ghkf", "rla", "qkr",
            "cjd", "dud", "wjd", "gktp", "tpdy", "sy", "ekd", "akf", "tlf",
            "tjd", "dhk", "rhk", "ghk", "thk", "whk", "chk", "khk", "phk",
            "rnjs", "dnjs", "wjdd", "tkdd", "rkdd", "skdd", "ekdd", "akdd"
        ]
        for pat in dubeolsikPatterns where lower.contains(pat) {
            return true
        }

        // Or 4+ consecutive English consonants that form valid Hangul syllables.
        var consecutiveConsonants = 0
        for ch in lower {
            if !englishVowels.contains(ch) {
                consecutiveConsonants += 1
                if consecutiveConsonants >= 4 { return true }
            } else {
                consecutiveConsonants = 0
            }
        }

        // ㅓ is the J key. Once it sits in a consonant run, the word is Dubeolsik
        // (어디, 어디서, 뭐야, 그래서), not a finished English word.
        var runLength = 0
        var runHasJ = false
        for ch in lower {
            if englishVowels.contains(ch) {
                if runLength >= 2 && runHasJ { return true }
                runLength = 0
                runHasJ = false
            } else {
                runLength += 1
                if ch == "j" { runHasJ = true }
            }
        }
        if runLength >= 2 && runHasJ { return true }

        // 여기/근데/내일 still contain an English vowel, so the rules above miss them.
        // `du` + a run starting with `rl` is 여기 (durl, durlsms). `dlf` is 내일.
        // `rms` only mid-word, so firms/forms stay English and rmsep (근데) converts.
        var runs: [String] = []
        var run = ""
        for ch in lower {
            if englishVowels.contains(ch) {
                if !run.isEmpty {
                    runs.append(run)
                    run = ""
                }
            } else {
                run.append(ch)
            }
        }
        if !run.isEmpty { runs.append(run) }
        if runs.contains(where: { $0.hasPrefix("dlf") }) { return true }
        if lower.hasPrefix("du") && runs.contains(where: { $0.hasPrefix("rl") }) { return true }
        if let rmsAt = runs.firstIndex(of: "rms"), rmsAt < runs.count - 1 { return true }

        return false
    }
}

// MARK: - macOS Input Source Manager (Carbon TIS)

enum InputSourceManager {
    static let koreanSourceID = "com.apple.inputmethod.Korean.2SetKorean"
    static let englishSourceID = "com.apple.keylayout.ABC"

    static func currentSourceID() -> String {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else {
            return ""
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    static func isKoreanActive() -> Bool {
        let id = currentSourceID()
        return id.contains("Korean") || id.contains("Hangul") || id.contains("Gureum")
    }

    @discardableResult
    static func selectInputSource(id targetID: String) -> Bool {
        let filter: [CFString: Any] = [kTISPropertyInputSourceID: targetID as CFString]
        guard let cfList = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource],
              let source = cfList.first else {
            return false
        }
        let status = TISSelectInputSource(source)
        return status == noErr
    }

    static func switchToEnglish() {
        if !selectInputSource(id: englishSourceID) {
            _ = selectInputSource(id: "com.apple.keylayout.US")
        }
    }

    static func switchToKorean() {
        _ = selectInputSource(id: koreanSourceID)
    }

    static func toggle() {
        if isKoreanActive() {
            switchToEnglish()
        } else {
            switchToKorean()
        }
    }
}

// MARK: - Foreground App Helper

enum AppContext {
    static let terminalBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "com.mitchellh.ghostty",
        "com.github.wez.wezterm",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper"
    ]

    static func isTerminalFrontmost() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return terminalBundleIDs.contains(bundleID)
    }
}

// MARK: - Words the user taught (exact keystrokes, not lowercased)

struct LearnedEnToKoList {
    static let acceptDefaultsKey = "learnedEnToKoAccept"
    static let rejectDefaultsKey = "learnedEnToKoReject"
    static let cap = 200

    private(set) var accept: [String] = []
    private(set) var reject: [String] = []

    func lookup(_ english: String) -> LearnedEnToKo? {
        if reject.contains(english) { return .reject }
        if accept.contains(english) { return .accept }
        return nil
    }

    mutating func rememberAccept(_ english: String) {
        guard !english.isEmpty else { return }
        reject.removeAll { $0 == english }
        accept.removeAll { $0 == english }
        accept.insert(english, at: 0)
        if accept.count > Self.cap { accept.removeLast(accept.count - Self.cap) }
    }

    mutating func rememberReject(_ english: String) {
        guard !english.isEmpty else { return }
        accept.removeAll { $0 == english }
        reject.removeAll { $0 == english }
        reject.insert(english, at: 0)
        if reject.count > Self.cap { reject.removeLast(reject.count - Self.cap) }
    }

    mutating func clear() {
        accept.removeAll()
        reject.removeAll()
    }

    static func loadFromDefaults() -> LearnedEnToKoList {
        var list = LearnedEnToKoList()
        list.accept = UserDefaults.standard.stringArray(forKey: acceptDefaultsKey) ?? []
        list.reject = UserDefaults.standard.stringArray(forKey: rejectDefaultsKey) ?? []
        return list
    }

    func saveToDefaults() {
        UserDefaults.standard.set(accept, forKey: Self.acceptDefaultsKey)
        UserDefaults.standard.set(reject, forKey: Self.rejectDefaultsKey)
    }
}

/// Backspaces still needed to erase an automatic English → Korean insertion.
struct PendingEnToKoUndo {
    let english: String
    var deletesLeft: Int

    init(english: String, insertedCharacterCount: Int) {
        self.english = english
        self.deletesLeft = insertedCharacterCount
    }

    /// Counts one user Backspace. True once the whole insertion is gone.
    mutating func noteBackspace() -> Bool {
        deletesLeft -= 1
        return deletesLeft <= 0
    }
}

// MARK: - Keyboard Event Injector & Tap Manager

final class KoEnFixEngine {
    static let shared = KoEnFixEngine()

    var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "isEnabled")
            onStateChange?()
        }
    }

    var mode: AutoConvertMode = .conservative {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "mode")
            onStateChange?()
        }
    }

    var convertOnTerminalEnter: Bool = true {
        didSet {
            UserDefaults.standard.set(convertOnTerminalEnter, forKey: "convertOnTerminalEnter")
            onStateChange?()
        }
    }

    private(set) var recentConversions: [String] = []
    private(set) var learnedList = LearnedEnToKoList()
    var onStateChange: (() -> Void)?

    private let buffer = WordBuffer()
    /// Prefix symbol immediately preceding the current word (`:`, `-`, `/`) for Vim / CLI flag context
    private var currentPrefixSymbol: Character? = nil
    /// Stores the last word right before a single Space, so pressing Shift+Space *after* Space also works!
    private var lastWordBeforeSpace: (sim: SimulationResult, wasKorean: Bool)? = nil
    /// Set after Space auto-converts English → Korean. Cleared unless the next
    /// keys are Backspaces that erase that insertion.
    private var pendingEnToKoUndo: PendingEnToKoUndo?
    private var isReplacing: Bool = false
    private let workerQueue = DispatchQueue(label: "com.dave.koen-fix.worker", qos: .userInteractive)
    fileprivate var eventTap: CFMachPort?

    private init() {
        if UserDefaults.standard.object(forKey: "isEnabled") != nil {
            isEnabled = UserDefaults.standard.bool(forKey: "isEnabled")
        }
        if let savedMode = UserDefaults.standard.string(forKey: "mode"),
           let m = AutoConvertMode(rawValue: savedMode) {
            mode = m
        }
        if UserDefaults.standard.object(forKey: "convertOnTerminalEnter") != nil {
            convertOnTerminalEnter = UserDefaults.standard.bool(forKey: "convertOnTerminalEnter")
        }
        learnedList = LearnedEnToKoList.loadFromDefaults()
    }

    func clearLearnedWords() {
        learnedList.clear()
        learnedList.saveToDefaults()
        onStateChange?()
    }

    private func learnAccept(_ english: String) {
        learnedList.rememberAccept(english)
        learnedList.saveToDefaults()
        onStateChange?()
    }

    private func learnReject(_ english: String) {
        learnedList.rememberReject(english)
        learnedList.saveToDefaults()
        onStateChange?()
    }

    private func cancelPendingEnToKoUndo() {
        pendingEnToKoUndo = nil
    }

    private func noteBackspaceTowardUndo() {
        guard var pending = pendingEnToKoUndo else { return }
        if pending.noteBackspace() {
            pendingEnToKoUndo = nil
            learnReject(pending.english)
        } else {
            pendingEnToKoUndo = pending
        }
    }

    func recordConversion(from src: String, to dst: String) {
        let entry = "\(src) → \(dst)"
        DispatchQueue.main.async {
            self.recentConversions.insert(entry, at: 0)
            if self.recentConversions.count > 5 {
                self.recentConversions.removeLast()
            }
            self.onStateChange?()
        }
    }

    func resetTracking() {
        buffer.reset()
        currentPrefixSymbol = nil
        lastWordBeforeSpace = nil
        cancelPendingEnToKoUndo()
    }

    func startEventTap() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = KoEnFixEngine.shared.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }
            return KoEnFixEngine.shared.handleEvent(proxy: proxy, type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else {
            return false
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Ignore our own synthetic events
        if event.getIntegerValueField(.eventSourceUserData) == SELF_EVENT_TAG {
            return Unmanaged.passRetained(event)
        }

        guard isEnabled, !isReplacing else {
            return Unmanaged.passRetained(event)
        }

        // Mouse clicks move the cursor -> reset word buffer
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            resetTracking()
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let hasCmd = flags.contains(.maskCommand)
        let hasCtrl = flags.contains(.maskControl)
        let hasOpt = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)

        // Any Cmd / Ctrl / Opt shortcut resets the buffer and passes through
        if hasCmd || hasCtrl || hasOpt {
            resetTracking()
            return Unmanaged.passRetained(event)
        }

        // Manual Trigger: Shift + Space (keyCode 49 with Shift)
        if keyCode == 49 && hasShift {
            return handleManualTrigger()
        }

        let inKorean = InputSourceManager.isKoreanActive()

        // Backspace (keyCode 51)
        if keyCode == 51 {
            noteBackspaceTowardUndo()
            if !buffer.isEmpty {
                buffer.handleUserBackspace(inKoreanMode: inKorean)
            } else {
                lastWordBeforeSpace = nil
            }
            return Unmanaged.passRetained(event)
        }

        // Space (keyCode 49, unshifted)
        if keyCode == 49 && !hasShift {
            return handleSpaceKey(inKorean: inKorean, originalEvent: event)
        }

        // Return / Enter (keyCode 36 or 76)
        if keyCode == 36 || keyCode == 76 {
            return handleEnterKey(inKorean: inKorean, originalEvent: event)
        }

        // Letter key (ANSI a-z)
        if let stroke = HangulAutomata.makeStroke(keyCode: keyCode, isShift: hasShift) {
            cancelPendingEnToKoUndo()
            lastWordBeforeSpace = nil
            buffer.append(stroke, inKoreanMode: inKorean)
            return Unmanaged.passRetained(event)
        }

        // Track ':' (Shift + ;, keyCode 41) or '-' (keyCode 27, unshifted) for Vim `:ㅂ`/`:ㅈㅂ` and CLI `-ㅣㅁ`
        if keyCode == 41 && hasShift {
            resetTracking()
            currentPrefixSymbol = ":"
            return Unmanaged.passRetained(event)
        }
        if keyCode == 27 && !hasShift {
            resetTracking()
            currentPrefixSymbol = "-"
            return Unmanaged.passRetained(event)
        }

        // Any other key (numbers, punctuation, arrows, Escape, Tab, etc.) resets word tracking
        resetTracking()
        return Unmanaged.passRetained(event)
    }

    // MARK: - Trigger Handlers

    private func handleManualTrigger() -> Unmanaged<CGEvent>? {
        cancelPendingEnToKoUndo()
        let inKorean = InputSourceManager.isKoreanActive()

        // Case 1: Active word currently being typed (before Space)
        if !buffer.isEmpty {
            let sim = buffer.snapshot()
            // Finished Hangul stays. Swallow the shortcut and keep the buffer:
            // letting Shift+Space through can insert a space or toggle the system
            // IME while this word is still being composed.
            if inKorean && !TypoDetector.shouldManualConvertKoToEn(sim: sim) {
                return nil
            }
            resetTracking()
            if inKorean {
                // Broken jamo only (스ㅕㅌ, ㅣㄴ, 치명ㄷ).
                performReplacement(
                    deleteCount: sim.backspacesInKoreanComposing,
                    switchToKorean: false,
                    insertText: sim.englishText,
                    fromLabel: sim.koreanText,
                    toLabel: sim.englishText
                )
            } else {
                // Convert English -> Korean, and teach Space to do this next time.
                learnAccept(sim.englishText)
                performReplacement(
                    deleteCount: sim.backspacesInEnglish,
                    switchToKorean: true,
                    insertText: sim.koreanText,
                    fromLabel: sim.englishText,
                    toLabel: sim.koreanText
                )
            }
            return nil // Consume Shift+Space
        }

        // Case 2: User pressed Shift+Space right AFTER pressing Space ("dkssud " -> "안녕 ")
        if let last = lastWordBeforeSpace {
            let sim = last.sim
            let finishedKorean = last.wasKorean && !TypoDetector.shouldManualConvertKoToEn(sim: sim)
            lastWordBeforeSpace = nil
            if !finishedKorean {
                if last.wasKorean {
                    // Since Space was already processed by the app, the Korean syllable was already committed!
                    let deleteCount = sim.committedKoreanCharCount + 1 // +1 for trailing Space
                    let replacement = sim.englishText + " "
                    performReplacement(
                        deleteCount: deleteCount,
                        switchToKorean: false,
                        insertText: replacement,
                        fromLabel: sim.koreanText,
                        toLabel: sim.englishText
                    )
                } else {
                    let deleteCount = sim.backspacesInEnglish + 1 // +1 for trailing Space
                    let replacement = sim.koreanText + " "
                    learnAccept(sim.englishText)
                    performReplacement(
                        deleteCount: deleteCount,
                        switchToKorean: true,
                        insertText: replacement,
                        fromLabel: sim.englishText,
                        toLabel: sim.koreanText
                    )
                }
                return nil // Consume Shift+Space
            }
            // Finished Hangul is already committed. Leave the word and toggle the IME below.
        }

        // Case 3: Buffer is empty -> simply toggle Korean/English IME
        InputSourceManager.toggle()
        return nil
    }

    private func handleSpaceKey(inKorean: Bool, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        cancelPendingEnToKoUndo()
        guard !buffer.isEmpty else {
            currentPrefixSymbol = nil
            lastWordBeforeSpace = nil
            return Unmanaged.passRetained(originalEvent)
        }

        let sim = buffer.snapshot()
        let prefix = currentPrefixSymbol
        buffer.reset()
        currentPrefixSymbol = nil

        if inKorean && TypoDetector.shouldAutoConvertKoToEn(sim: sim, mode: mode, prefixSymbol: prefix) {
            lastWordBeforeSpace = nil
            performReplacement(
                deleteCount: sim.backspacesInKoreanComposing,
                switchToKorean: false,
                insertText: sim.englishText + " ",
                fromLabel: sim.koreanText,
                toLabel: sim.englishText
            )
            return nil // Suppress original Space; our replacement appends " "
        }

        if !inKorean && TypoDetector.shouldAutoConvertEnToKo(
            sim: sim,
            mode: mode,
            learned: learnedList.lookup(sim.englishText)
        ) {
            lastWordBeforeSpace = nil
            // korean syllables plus the trailing space we insert.
            pendingEnToKoUndo = PendingEnToKoUndo(
                english: sim.englishText,
                insertedCharacterCount: sim.koreanText.count + 1
            )
            performReplacement(
                deleteCount: sim.backspacesInEnglish,
                switchToKorean: true,
                insertText: sim.koreanText + " ",
                fromLabel: sim.englishText,
                toLabel: sim.koreanText
            )
            return nil // Suppress original Space; our replacement appends " "
        }

        // Not auto-converted: remember this word in case the user presses Shift+Space right after Space!
        lastWordBeforeSpace = (sim: sim, wasKorean: inKorean)
        return Unmanaged.passRetained(originalEvent)
    }

    private func handleEnterKey(inKorean: Bool, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard !buffer.isEmpty else {
            resetTracking()
            return Unmanaged.passRetained(originalEvent)
        }

        let sim = buffer.snapshot()
        let prefix = currentPrefixSymbol
        resetTracking()

        // If inside a terminal (tmux / zsh) and user typed a broken-jamo command or known CLI/Vim command
        // like `ㅣㄴ`, `ㅅㅡㅕㅌ`, `햣`, `:ㅂ`, `:ㅈㅂ` and hit Enter: replace with English (`ls`, `tmux`, `git`, `q`, `wq`) without executing yet!
        if convertOnTerminalEnter && inKorean && AppContext.isTerminalFrontmost() {
            if TypoDetector.shouldAutoConvertKoToEn(sim: sim, mode: .conservative, prefixSymbol: prefix) {
                performReplacement(
                    deleteCount: sim.backspacesInKoreanComposing,
                    switchToKorean: false,
                    insertText: sim.englishText,
                    fromLabel: sim.koreanText,
                    toLabel: sim.englishText
                )
                return nil // Suppress Enter so user sees the fixed command on prompt before running
            }
        }

        return Unmanaged.passRetained(originalEvent)
    }

    // MARK: - Deterministic Replacement Sequencer

    /// Deterministic 3-phase replacement that avoids all macOS KoreanIM race conditions:
    /// - For Korean -> English:
    ///   1) Send `deleteCount` Backspaces while STILL in Korean mode (unwinds KoreanIM markedText + committed chars)
    ///   2) Switch input source to English (`ABC`)
    ///   3) Inject English text in `ABC` mode
    /// - For English -> Korean:
    ///   1) Send `deleteCount` Backspaces while STILL in English (`ABC`) mode
    ///   2) Inject composed Korean Unicode text while STILL in `ABC` mode (bypasses KoreanIM composition!)
    ///   3) Switch input source to Korean (`2SetKorean`)
    private func performReplacement(
        deleteCount: Int,
        switchToKorean: Bool,
        insertText: String,
        fromLabel: String,
        toLabel: String
    ) {
        isReplacing = true
        recordConversion(from: fromLabel, to: toLabel)

        workerQueue.async { [weak self] in
            defer {
                usleep(15_000)
                self?.isReplacing = false
            }

            let src = CGEventSource(stateID: .privateState)

            // Phase 1: Delete existing characters in the CURRENT input mode
            if deleteCount > 0 {
                for _ in 0..<deleteCount {
                    Self.postKey(keyCode: 51, flags: [], source: src)
                    usleep(2_500)
                }
                usleep(18_000)
            }

            if switchToKorean {
                // Direction: English -> Korean
                // Phase 2: Inject Unicode Hangul while STILL in ABC mode so KoreanIM never intercepts it
                Self.postUnicodeString(insertText, source: src)
                usleep(18_000)

                // Phase 3: Switch IME to Korean (with retry check)
                DispatchQueue.main.sync {
                    InputSourceManager.switchToKorean()
                }
                usleep(12_000)
                if !InputSourceManager.isKoreanActive() {
                    DispatchQueue.main.sync {
                        InputSourceManager.switchToKorean()
                    }
                }
            } else {
                // Direction: Korean -> English
                // Phase 2: Switch IME to English (ABC) first
                DispatchQueue.main.sync {
                    InputSourceManager.switchToEnglish()
                }
                usleep(18_000)
                if InputSourceManager.isKoreanActive() {
                    DispatchQueue.main.sync {
                        InputSourceManager.switchToEnglish()
                    }
                    usleep(12_000)
                }

                // Phase 3: Inject English text now that ABC is active
                Self.postUnicodeString(insertText, source: src)
            }
        }
    }

    private static func postKey(keyCode: CGKeyCode, flags: CGEventFlags, source: CGEventSource?) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: SELF_EVENT_TAG)
        up.setIntegerValueField(.eventSourceUserData, value: SELF_EVENT_TAG)
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    private static func postUnicodeString(_ text: String, source: CGEventSource?) {
        for ch in text {
            if ch == " " {
                postKey(keyCode: 49, flags: [], source: source)
                usleep(2_000)
                continue
            }
            var utf16 = Array(String(ch).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            down.flags = []
            up.flags = []
            down.setIntegerValueField(.eventSourceUserData, value: SELF_EVENT_TAG)
            up.setIntegerValueField(.eventSourceUserData, value: SELF_EVENT_TAG)
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
            usleep(2_500)
        }
    }
}

// MARK: - Status Bar Menu UI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var tapRetryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        KoEnFixEngine.shared.onStateChange = { [weak self] in
            self?.rebuildMenu()
        }

        // Check Accessibility permission & start CGEventTap
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            _ = KoEnFixEngine.shared.startEventTap()
        } else {
            // Poll every 2 seconds until user grants Accessibility permission in System Settings
            tapRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    if KoEnFixEngine.shared.startEventTap() {
                        timer.invalidate()
                        self?.tapRetryTimer = nil
                        self?.rebuildMenu()
                    }
                }
            }
        }
        rebuildMenu()
    }

    private lazy var appIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url),
           image.isValid {
            return image
        }
        return NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 18, height: 18))
    }()

    private func setupStatusBar() {
        // A fixed width keeps the item visible. squareLength can collapse an image
        // that has not been rasterized yet.
        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        updateStatusButton()
    }

    /// Menu-bar image of the app icon. Finder's squircle mask is not applied here,
    /// so the mark is clipped to the same corner ratio. The bitmap is drawn up front
    /// because a deferred status-item image can be dropped. Off-state is dimmed, and a
    /// missing Accessibility grant gets a corner dot because the bar has no room for text.
    private func makeStatusImage(dimmed: Bool, warning: Bool) -> NSImage {
        let side: CGFloat = 18
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = Int((side * scale).rounded())
        let fallback = NSImage(size: NSSize(width: side, height: side))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return fallback
        }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return fallback
        }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        let rect = NSRect(x: 0, y: 0, width: side, height: side)
        ctx.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: side * 0.2237, yRadius: side * 0.2237).addClip()
        appIcon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: dimmed ? 0.38 : 1)
        ctx.restoreGraphicsState()
        if warning {
            let diameter = side * 0.34
            let dot = NSRect(x: side - diameter, y: side - diameter, width: diameter, height: diameter)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: dot.insetBy(dx: -0.8, dy: -0.8)).fill()
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let trusted = AXIsProcessTrusted()
        let enabled = KoEnFixEngine.shared.isEnabled
        let image = makeStatusImage(dimmed: trusted && !enabled, warning: !trusted)
        image.isTemplate = false
        button.image = image
        button.image?.isTemplate = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.title = ""
        if !trusted {
            button.toolTip = "KoEnFix — 손쉬운 사용 권한이 필요합니다"
            button.setAccessibilityLabel("KoEnFix, 손쉬운 사용 권한 필요")
        } else if !enabled {
            button.toolTip = "KoEnFix (끔)"
            button.setAccessibilityLabel("KoEnFix, 꺼짐")
        } else {
            button.toolTip = "KoEnFix"
            button.setAccessibilityLabel("KoEnFix")
        }
    }

    private func rebuildMenu() {
        updateStatusButton()
        let menu = NSMenu()
        let engine = KoEnFixEngine.shared
        let trusted = AXIsProcessTrusted()

        let header = NSMenuItem(title: "KoEnFix — 한/영 오타 자동 교정", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if !trusted {
            let warnItem = NSMenuItem(
                title: "⚠️ 손쉬운 사용(Accessibility) 권한 필요 (클릭하여 설정 열기)",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            warnItem.target = self
            menu.addItem(warnItem)
        }

        menu.addItem(NSMenuItem.separator())

        let enableItem = NSMenuItem(
            title: "활성화 (Shift + Space 즉시 변환)",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enableItem.target = self
        enableItem.state = engine.isEnabled ? .on : .off
        menu.addItem(enableItem)

        menu.addItem(NSMenuItem.separator())

        let modeHeader = NSMenuItem(title: "자동 변환 모드 (Space 입력 시)", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)

        for m in AutoConvertMode.allCases {
            let item = NSMenuItem(title: m.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = m.rawValue
            item.state = (engine.mode == m) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let termEnterItem = NSMenuItem(
            title: "터미널(tmux)에서 Enter 시 명령어 교정",
            action: #selector(toggleTerminalEnter),
            keyEquivalent: ""
        )
        termEnterItem.target = self
        termEnterItem.state = engine.convertOnTerminalEnter ? .on : .off
        menu.addItem(termEnterItem)

        menu.addItem(NSMenuItem.separator())

        appendLearnedMenu(menu, title: "Space로 바꿀 영문", words: engine.learnedList.accept)
        appendLearnedMenu(menu, title: "그대로 둘 영문", words: engine.learnedList.reject)
        if !engine.learnedList.accept.isEmpty || !engine.learnedList.reject.isEmpty {
            let clearItem = NSMenuItem(title: "학습 목록 비우기", action: #selector(clearLearnedWords), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }

        menu.addItem(NSMenuItem.separator())

        let recentHeader = NSMenuItem(title: "최근 변환 내역", action: nil, keyEquivalent: "")
        recentHeader.isEnabled = false
        menu.addItem(recentHeader)

        if engine.recentConversions.isEmpty {
            let emptyItem = NSMenuItem(title: "  (아직 변환 내역 없음)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for entry in engine.recentConversions {
                let item = NSMenuItem(title: "  \(entry)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "종료 (Quit)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func appendLearnedMenu(_ menu: NSMenu, title: String, words: [String]) {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if words.isEmpty {
            let emptyItem = NSMenuItem(title: "  (없음)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }
        for word in words.prefix(8) {
            let item = NSMenuItem(title: "  \(word)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if words.count > 8 {
            let more = NSMenuItem(title: "  외 \(words.count - 8)개", action: nil, keyEquivalent: "")
            more.isEnabled = false
            menu.addItem(more)
        }
    }

    @objc private func clearLearnedWords() {
        KoEnFixEngine.shared.clearLearnedWords()
    }

    @objc private func toggleEnabled() {
        KoEnFixEngine.shared.isEnabled.toggle()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let m = AutoConvertMode(rawValue: raw) else { return }
        KoEnFixEngine.shared.mode = m
    }

    @objc private func toggleTerminalEnter() {
        KoEnFixEngine.shared.convertOnTerminalEnter.toggle()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Built-in Automated Self-Tests (`--self-test`)

func runSelfTests() -> Int32 {
    var failures = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("❌ FAIL: \(message)\n", stderr)
            failures += 1
        } else {
            print("✅ PASS: \(message)")
        }
    }

    // 1. Automata composition & backspace calculation tests
    do {
        let tmuxStrokes = HangulAutomata.strokes(fromEnglish: "tmux")!
        let sim = HangulAutomata.simulate(tmuxStrokes)
        expect(sim.koreanText == "스ㅕㅌ", "tmux in Dubeolsik should compose as '스ㅕㅌ' (got '\(sim.koreanText)')")
        expect(sim.committedScalars == ["스", "ㅕ"], "tmux committed scalars should be ['스', 'ㅕ']")
        expect(sim.composingStrokes.count == 1, "tmux composing strokes should be 1 ('ㅌ')")
        expect(sim.backspacesInKoreanComposing == 3, "tmux in Korean composing state requires 3 backspaces")

        let gitStrokes = HangulAutomata.strokes(fromEnglish: "git")!
        let gitSim = HangulAutomata.simulate(gitStrokes)
        expect(gitSim.koreanText == "햣", "git in Dubeolsik should compose as '햣' (got '\(gitSim.koreanText)')")
        expect(gitSim.committedScalars.isEmpty, "git has 0 committed scalars before Space")
        expect(gitSim.composingStrokes.count == 3, "git has 3 composing strokes in markedText")
        expect(gitSim.backspacesInKoreanComposing == 3, "git in Korean composing state requires 3 backspaces")

        let helloStrokes = HangulAutomata.strokes(fromEnglish: "dkssudgktpdy")!
        let helloSim = HangulAutomata.simulate(helloStrokes)
        expect(helloSim.koreanText == "안녕하세요", "dkssudgktpdy -> '안녕하세요' (got '\(helloSim.koreanText)')")

        let hangulStrokes = HangulAutomata.strokes(fromEnglish: "gksrmf")!
        let hangulSim = HangulAutomata.simulate(hangulStrokes)
        expect(hangulSim.koreanText == "한글", "gksrmf -> '한글' (got '\(hangulSim.koreanText)')")
        expect(hangulSim.committedScalars == ["한"], "gksrmf committed scalar is ['한']")
        expect(hangulSim.composingStrokes.count == 3, "gksrmf composing strokes for '글' is 3")
        expect(hangulSim.backspacesInKoreanComposing == 4, "gksrmf in Korean composing requires 4 backspaces")

        // Compound vowel + compound jongseong + jongseong split (연음): 닭 + ㅏ = 달가
        let dalgaStrokes = HangulAutomata.strokes(fromEnglish: "ekfrk")!
        let dalgaSim = HangulAutomata.simulate(dalgaStrokes)
        expect(dalgaSim.koreanText == "달가", "ekfrk -> '달가' (got '\(dalgaSim.koreanText)')")
        expect(dalgaSim.committedScalars == ["달"], "ekfrk committed scalar is ['달']")
        expect(dalgaSim.composingStrokes.count == 2, "ekfrk composing strokes for '가' is 2")
        expect(dalgaSim.backspacesInKoreanComposing == 3, "ekfrk in Korean composing requires 3 backspaces")
    }

    // 2. WordBuffer mid-word backspace synchronization tests
    do {
        let buf = WordBuffer()
        for s in HangulAutomata.strokes(fromEnglish: "gksrmf")! {
            buf.append(s, inKoreanMode: true)
        }
        expect(buf.snapshot().koreanText == "한글", "WordBuffer initial '한글'")
        // Press backspace once -> '글' becomes '그'
        buf.handleUserBackspace(inKoreanMode: true)
        expect(buf.snapshot().koreanText == "한그", "WordBuffer after 1 backspace -> '한그' (got '\(buf.snapshot().koreanText)')")
        // Press backspace twice more -> '그' cleared, leaving committed '한'
        buf.handleUserBackspace(inKoreanMode: true)
        buf.handleUserBackspace(inKoreanMode: true)
        expect(buf.snapshot().koreanText == "한", "WordBuffer after 3 backspaces -> '한' (got '\(buf.snapshot().koreanText)')")
        // Press backspace once more -> entire committed '한' is deleted!
        buf.handleUserBackspace(inKoreanMode: true)
        expect(buf.isEmpty, "WordBuffer after 4th backspace is completely empty")
    }

    // 3. Conservative Mode detection tests
    do {
        for cmd in ["tmux", "ls", "cd", "git", "curl", "sudo", "nvim", "claude", "docker", "status", "clear"] {
            let sim = HangulAutomata.simulate(HangulAutomata.strokes(fromEnglish: cmd)!)
            expect(
                TypoDetector.shouldAutoConvertKoToEn(sim: sim, mode: .conservative),
                "Conservative mode should auto-convert '\(sim.koreanText)' -> '\(cmd)'"
            )
        }

        // Intentional Korean slang & real Korean words must NOT auto-convert in Conservative mode
        for safeKo in ["ㅋㅋㅋ", "ㅎㅎ", "ㅠㅠ", "ㅜㅜ", "ㅇㅇ", "ㄱㅅ", "ㅈㅅ", "안녕", "한글", "해", "내"] {
            // Find strokes that produce safeKo or test directly
            let EnMap: [String: String] = [
                "ㅋㅋㅋ": "zzz", "ㅎㅎ": "gg", "ㅠㅠ": "bb", "ㅜㅜ": "nn",
                "ㅇㅇ": "dd", "ㄱㅅ": "rt", "ㅈㅅ": "wt", "안녕": "dkssud",
                "한글": "gksrmf", "해": "go", "내": "so"
            ]
            if let en = EnMap[safeKo], let strokes = HangulAutomata.strokes(fromEnglish: en) {
                let sim = HangulAutomata.simulate(strokes)
                expect(
                    !TypoDetector.shouldAutoConvertKoToEn(sim: sim, mode: .conservative),
                    "Conservative mode must NOT auto-convert intentional Korean '\(sim.koreanText)'"
                )
            }
        }
        // Vim colon commands (`:ㅂ` -> `:q`, `:ㅈㅂ` -> `:wq`) and CLI flags (`-ㅣㅁ` -> `-la`, `-ㄱㄹ` -> `-rf`)
        for vimCmd in ["q", "w", "wq", "qa"] {
            let sim = HangulAutomata.simulate(HangulAutomata.strokes(fromEnglish: vimCmd)!)
            expect(
                TypoDetector.shouldAutoConvertKoToEn(sim: sim, mode: .conservative, prefixSymbol: ":"),
                "Conservative mode should auto-convert Vim command ':\(sim.koreanText)' -> ':\(vimCmd)'"
            )
        }
        for flag in ["la", "rf"] {
            let sim = HangulAutomata.simulate(HangulAutomata.strokes(fromEnglish: flag)!)
            expect(
                TypoDetector.shouldAutoConvertKoToEn(sim: sim, mode: .conservative, prefixSymbol: "-"),
                "Conservative mode should auto-convert CLI flag '-\(sim.koreanText)' -> '-\(flag)'"
            )
        }
    }
    do {
        for (en, expectedKo) in [("dkssud", "안녕"), ("gksrmf", "한글"), ("dkssudgktpdy", "안녕하세요"), ("qksrkqtmqslek", "반갑습니다"), ("djeltj", "어디서"), ("djel", "어디"), ("anjdi", "뭐야"), ("rmfotj", "그래서"), ("durl", "여기"), ("durlsms", "여기는"), ("rmsep", "근데"), ("sodlf", "내일"), ("sodlfdms", "내일은")] {
            let sim = HangulAutomata.simulate(HangulAutomata.strokes(fromEnglish: en)!)
            expect(sim.koreanText == expectedKo, "\(en) composes to \(expectedKo)")
            expect(
                TypoDetector.shouldAutoConvertEnToKo(sim: sim, mode: .aggressive),
                "Aggressive mode should auto-convert '\(en)' -> '\(expectedKo)'"
            )
            expect(
                !TypoDetector.shouldAutoConvertEnToKo(sim: sim, mode: .conservative),
                "Conservative mode must NOT auto-convert En->Ko '\(en)' on Space"
            )
        }

        for realEn in ["tmux", "claude", "docker", "status", "work", "form", "gold", "milk", "django", "djvu", "vuejs", "adjust", "enjoy", "subject", "forms", "firms", "charms", "alarms", "girl", "curl", "charley", "dharmsala"] {
            let sim = HangulAutomata.simulate(HangulAutomata.strokes(fromEnglish: realEn)!)
            expect(
                !TypoDetector.shouldAutoConvertEnToKo(sim: sim, mode: .aggressive),
                "Aggressive mode must NOT auto-convert real English word '\(realEn)'"
            )
        }
    }

    // 4. Shift+Space leaves finished Hangul alone and still converts broken jamo.
    do {
        func simulated(_ en: String) -> SimulationResult {
            HangulAutomata.simulate(HangulAutomata.strokes(fromEnglish: en)!)
        }
        for (en, ko) in [("dkssud", "안녕"), ("gksrmf", "한글"), ("go", "해"), ("dkssudgktpdy", "안녕하세요"), ("gks", "한")] {
            let sim = simulated(en)
            expect(sim.koreanText == ko, "\(en) composes to \(ko) (got '\(sim.koreanText)')")
            expect(
                !TypoDetector.shouldManualConvertKoToEn(sim: sim),
                "Shift+Space leaves finished Hangul '\(ko)' alone"
            )
        }
        for en in ["tmux", "ls", "claude"] {
            let sim = simulated(en)
            expect(
                TypoDetector.shouldManualConvertKoToEn(sim: sim),
                "Shift+Space still converts broken jamo '\(sim.koreanText)' -> '\(en)'"
            )
        }
        let git = simulated("git")
        expect(
            !TypoDetector.shouldManualConvertKoToEn(sim: git),
            "Shift+Space leaves the finished syllable '\(git.koreanText)' alone"
        )
        expect(
            TypoDetector.shouldAutoConvertKoToEn(sim: git, mode: .conservative),
            "Space still auto-converts '\(git.koreanText)' -> git"
        )
    }

    // 5. User corrections outrank the heuristic and are mutually exclusive.
    do {
        var list = LearnedEnToKoList()
        list.rememberAccept("work")
        let work = HangulAutomata.simulate(HangulAutomata.strokes(fromEnglish: "work")!)
        expect(
            TypoDetector.shouldAutoConvertEnToKo(sim: work, mode: .aggressive, learned: list.lookup("work")),
            "A Shift+Space En->Ko correction makes Space convert 'work'"
        )
        expect(
            !TypoDetector.shouldAutoConvertEnToKo(sim: work, mode: .conservative, learned: list.lookup("work")),
            "Conservative mode still leaves learned En->Ko to Shift+Space"
        )
        expect(list.lookup("work") == .accept, "Accept list records 'work'")

        let whereFrom = HangulAutomata.simulate(HangulAutomata.strokes(fromEnglish: "djeltj")!)
        list.rememberReject("djeltj")
        expect(
            !TypoDetector.shouldAutoConvertEnToKo(sim: whereFrom, mode: .aggressive, learned: list.lookup("djeltj")),
            "Deleting an automatic conversion keeps 'djeltj' in English"
        )
        list.rememberAccept("djeltj")
        expect(list.lookup("djeltj") == .accept, "A later manual conversion removes the reject entry")
        expect(list.reject.isEmpty, "Reject list drops a word the user converted manually")

        var undo = PendingEnToKoUndo(english: "djeltj", insertedCharacterCount: whereFrom.koreanText.count + 1)
        expect(undo.deletesLeft == 4, "어디서 plus its trailing space takes 4 backspaces")
        expect(!undo.noteBackspace(), "The first backspace leaves part of the insertion")
        expect(!undo.noteBackspace(), "The second backspace leaves part of the insertion")
        expect(!undo.noteBackspace(), "The third backspace leaves part of the insertion")
        expect(undo.noteBackspace(), "The fourth backspace erases the automatic conversion")
    }

    if failures == 0 {
        print("\n🎉 All KoEnFix self-tests passed!")
        return 0
    } else {
        fputs("\n💥 \(failures) test(s) failed.\n", stderr)
        return 1
    }
}

// MARK: - Entry Point

if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTests())
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Menu Bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
