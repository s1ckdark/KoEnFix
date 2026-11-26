import Cocoa
import Carbon

// MARK: - Constants & Types

private let SELF_EVENT_TAG: Int64   = 0x4B4F_454E // "KOEN"
private let REPLAY_EVENT_TAG: Int64 = 0x4B4F_5250 // "KORP"

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

/// What KoEnFix does when a Ctrl combo arrives while a Korean input source is active.
enum CtrlComboAction: Equatable {
    /// A system input-source shortcut such as Ctrl+Space. The system handles it.
    case passThrough
    /// Leave the text alone and switch the input source to English.
    case switchInputSource
    /// Replace the pending English typo and switch the input source to English.
    case convertWord(SimulationResult)
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

    /// Ctrl combo in Korean mode. The pending word converts when Space would convert it.
    /// Everything else only switches the input source; manual mode never changes the text.
    static func ctrlComboAction(
        isInputSourceSwitchHotKey: Bool,
        sim: SimulationResult?,
        mode: AutoConvertMode,
        prefixSymbol: Character?
    ) -> CtrlComboAction {
        if isInputSourceSwitchHotKey { return .passThrough }
        guard let sim, shouldAutoConvertKoToEn(sim: sim, mode: mode, prefixSymbol: prefixSymbol) else {
            return .switchInputSource
        }
        return .convertWord(sim)
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

// MARK: - macOS Input Source Manager (Carbon TIS + CJKV Focus/Shortcut Sync)

private final class TemporaryInputWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum InputSourceManager {
    struct SymbolicHotKey: Equatable {
        let keyCode: CGKeyCode
        let modifiers: CGEventFlags
    }

    static let koreanSourceID = "com.apple.inputmethod.Korean.2SetKorean"
    static let englishSourceID = "com.apple.keylayout.ABC"

    private static var temporaryWindow: TemporaryInputWindow?

    static func sourceID(of source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return ""
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue() == kCFBooleanTrue
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    static func isKoreanSourceID(_ id: String) -> Bool {
        return id.contains("Korean") || id.contains("Hangul") || id.contains("Gureum")
    }

    static func currentSourceID() -> String {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return ""
        }
        return sourceID(of: src)
    }

    static func isKoreanActive() -> Bool {
        return isKoreanSourceID(currentSourceID())
    }

    static func selectableKeyboardSources() -> [TISInputSource] {
        guard let cfList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        let kbdCategory = kTISCategoryKeyboardInputSource as String
        return cfList.filter { src in
            stringProperty(src, kTISPropertyInputSourceCategory) == kbdCategory &&
            boolProperty(src, kTISPropertyInputSourceIsSelectCapable) &&
            boolProperty(src, kTISPropertyInputSourceIsEnabled)
        }
    }

    static func preferredKoreanSource() -> TISInputSource? {
        let sources = selectableKeyboardSources()
        if let exact = sources.first(where: { sourceID(of: $0) == koreanSourceID }) {
            return exact
        }
        return sources.first(where: { isKoreanSourceID(sourceID(of: $0)) })
    }

    static func preferredEnglishSource() -> TISInputSource? {
        let sources = selectableKeyboardSources()
        if let abc = sources.first(where: { sourceID(of: $0) == englishSourceID }) {
            return abc
        }
        if let us = sources.first(where: { sourceID(of: $0) == "com.apple.keylayout.US" }) {
            return us
        }
        if let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           !isKoreanSourceID(sourceID(of: ascii)) {
            return ascii
        }
        return sources.first(where: { !isKoreanSourceID(sourceID(of: $0)) })
    }

    @discardableResult
    static func selectInputSource(id targetID: String) -> Bool {
        let filter: [CFString: Any] = [kTISPropertyInputSourceID: targetID as CFString]
        guard let cfList = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource],
              let source = cfList.first else {
            return false
        }
        return TISSelectInputSource(source) == noErr
    }

    @discardableResult
    static func switchToEnglish() -> Bool {
        if let src = preferredEnglishSource() {
            return TISSelectInputSource(src) == noErr
        }
        if selectInputSource(id: englishSourceID) {
            return true
        }
        return selectInputSource(id: "com.apple.keylayout.US")
    }

    @discardableResult
    static func switchToKorean() -> Bool {
        if let src = preferredKoreanSource() {
            return TISSelectInputSource(src) == noErr
        }
        return selectInputSource(id: koreanSourceID)
    }

    /// Converts legacy Carbon modifier bitmasks from `com.apple.symbolichotkeys` to `CGEventFlags`.
    static func convertCarbonModifiersToCGFlags(_ carbonFlags: Int) -> CGEventFlags {
        var flags: CGEventFlags = []
        if (carbonFlags & 131072) != 0  { flags.insert(.maskShift) }
        if (carbonFlags & 262144) != 0  { flags.insert(.maskControl) }
        if (carbonFlags & 524288) != 0  { flags.insert(.maskAlternate) }
        if (carbonFlags & 1048576) != 0 { flags.insert(.maskCommand) }
        return flags
    }

    /// Parses a symbolic hotkey entry (`"60"` = previous input source, `"61"` = next input source).
    static func parseSymbolicHotKey(from hotKeys: [String: Any], id: String) -> SymbolicHotKey? {
        guard let entry = hotKeys[id] as? [String: Any] else { return nil }
        if let enabled = entry["enabled"] as? Bool, !enabled {
            return nil
        }
        guard let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [Int],
              params.count >= 3 else {
            return nil
        }
        let rawKeyCode = params[1]
        let rawModifiers = params[2]
        guard rawKeyCode >= 0 && rawKeyCode < 128 else { return nil }
        let modifiers = convertCarbonModifiersToCGFlags(rawModifiers)
        guard !modifiers.isEmpty else { return nil }
        return SymbolicHotKey(keyCode: CGKeyCode(rawKeyCode), modifiers: modifiers)
    }

    /// The Shift/Ctrl/Opt/Cmd part of event flags. Device-dependent bits are dropped.
    static func shortcutModifiers(of flags: CGEventFlags) -> CGEventFlags {
        return flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
    }

    /// The modifiers a held key is replayed with: the shortcut modifiers plus Fn, which arrow
    /// keys need to stay Home, End and Page keys.
    static func keyStrokeModifiers(of flags: CGEventFlags) -> CGEventFlags {
        var modifiers = shortcutModifiers(of: flags)
        if flags.contains(.maskSecondaryFn) {
            modifiers.insert(.maskSecondaryFn)
        }
        return modifiers
    }

    /// Generic and device-dependent flag bits of each modifier. A real key event carries both.
    /// Fn has no device bit.
    private static let modifierBits: [(flag: CGEventFlags, deviceBits: CGEventFlags)] = [
        (.maskShift,       CGEventFlags(rawValue: 0x0006)), // left and right Shift
        (.maskControl,     CGEventFlags(rawValue: 0x2001)), // left and right Ctrl
        (.maskAlternate,   CGEventFlags(rawValue: 0x0060)), // left and right Option
        (.maskCommand,     CGEventFlags(rawValue: 0x0018)), // left and right Cmd
        (.maskSecondaryFn, [])
    ]

    /// Generic and device bits of every modifier in `flags`.
    static func modifierBits(of flags: CGEventFlags) -> CGEventFlags {
        var bits: CGEventFlags = []
        for (flag, deviceBits) in modifierBits where flags.contains(flag) {
            bits.insert(flag)
            bits.formUnion(deviceBits)
        }
        return bits
    }

    /// Flags for a replayed key stroke. From the keyboard's flags it keeps only the device bits
    /// of the stroke's own modifiers, so a Shift or Fn pressed in the meantime cannot ride along.
    /// `modifiers` are always present, even when the user has released them.
    static func keyStrokeFlags(from flags: CGEventFlags, modifiers: CGEventFlags) -> CGEventFlags {
        return flags
            .subtracting(modifierBits(of: flags))
            .union(flags.intersection(modifierBits(of: modifiers)))
            .union(modifiers)
    }

    /// "Select the previous input source" (60) and "Select next source in Input menu" (61).
    static func inputSourceSwitchHotKeys(from hotKeys: [String: Any]) -> [SymbolicHotKey] {
        return ["60", "61"].compactMap { parseSymbolicHotKey(from: hotKeys, id: $0) }
    }

    static func inputSourceSwitchHotKeys() -> [SymbolicHotKey] {
        guard let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let hotKeys = domain["AppleSymbolicHotKeys"] as? [String: Any] else {
            return []
        }
        return inputSourceSwitchHotKeys(from: hotKeys)
    }

    /// True when the key and its Shift/Ctrl/Opt/Cmd modifiers equal one of `hotKeys`.
    static func matchesInputSourceSwitchHotKey(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags,
        hotKeys: [SymbolicHotKey]
    ) -> Bool {
        let modifiers = shortcutModifiers(of: modifiers)
        return hotKeys.contains { $0.keyCode == keyCode && $0.modifiers == modifiers }
    }

    static func previousInputSourceHotKey() -> SymbolicHotKey? {
        guard let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let hotKeys = domain["AppleSymbolicHotKeys"] as? [String: Any] else {
            return nil
        }
        if let prev = parseSymbolicHotKey(from: hotKeys, id: "60") {
            return prev
        }
        // When only 2 keyboard input sources are enabled, "Select next source" (61) reaches the exact same target.
        if selectableKeyboardSources().count == 2,
           let next = parseSymbolicHotKey(from: hotKeys, id: "61") {
            return next
        }
        return nil
    }

    /// Reliably switches the focused app's active input context to English (`ABC`).
    /// Must be called from `workerQueue` (never the main thread).
    static func activateEnglishFromWorker(postShortcut: (SymbolicHotKey) -> Void) {
        DispatchQueue.main.sync {
            _ = switchToEnglish()
        }
        usleep(25_000)

        let stillKorean = DispatchQueue.main.sync { isKoreanActive() }
        guard stillKorean else { return }

        DispatchQueue.main.sync {
            _ = switchToEnglish()
        }
        usleep(20_000)

        let stillKoreanAfterRetry = DispatchQueue.main.sync { isKoreanActive() }
        if stillKoreanAfterRetry, let hotKey = DispatchQueue.main.sync(execute: { previousInputSourceHotKey() }) {
            postShortcut(hotKey)
            usleep(35_000)
        }
    }

    /// Reliably switches the focused app's active input context to Korean (`2SetKorean`).
    /// Calling `TISSelectInputSource` directly on a CJKV `InputMode` from a background `LSUIElement`
    /// updates only the menu-bar icon while leaving the focused app's `TSMDocument` in `ABC`.
    /// Must be called from `workerQueue` (never the main thread).
    static func activateKoreanFromWorker(postShortcut: (SymbolicHotKey) -> Void) {
        // Tier 1: Native WindowServer input-source shortcut (zero focus change).
        let prep: (hotKey: SymbolicHotKey?, targetID: String, needsBounceWait: Bool, needsEnglishReset: Bool) = DispatchQueue.main.sync {
            let hotKey = previousInputSourceHotKey()
            let koSrc = preferredKoreanSource()
            let targetID = koSrc.map { sourceID(of: $0) } ?? koreanSourceID
            let kbdCount = selectableKeyboardSources().count
            let currentlyKorean = isKoreanActive()

            if hotKey != nil, let koSrc = koSrc, kbdCount > 2 {
                // Put target Korean source into MRU history right before bouncing to English.
                _ = TISSelectInputSource(koSrc)
                return (hotKey, targetID, true, true)
            }
            return (hotKey, targetID, false, currentlyKorean)
        }

        if let hotKey = prep.hotKey {
            if prep.needsBounceWait {
                usleep(20_000)
            }
            if prep.needsEnglishReset {
                // Ensure TIS is synced to English (`ABC`) before firing "Select previous input source",
                // even if an earlier out-of-focus TIS call left the menu bar stuck on Korean.
                DispatchQueue.main.sync {
                    _ = switchToEnglish()
                }
                usleep(20_000)
            }

            postShortcut(hotKey)

            for _ in 0..<15 {
                usleep(8_000)
                let activated = DispatchQueue.main.sync {
                    let cur = currentSourceID()
                    return cur == prep.targetID || isKoreanSourceID(cur)
                }
                if activated {
                    // Allow KoreanIM session activation to finish settling on the focused app.
                    usleep(15_000)
                    return
                }
            }
        }

        // Tier 2 Fallback (when shortcut 60 is disabled or intercepted):
        // Select Korean in TIS and briefly activate a 3x3 transparent NSTextView window so
        // macOS completes the CJKV IMKServer handoff, then restore focus to the previous app.
        activateKoreanViaTemporaryWindow()
    }

    private static func activateKoreanViaTemporaryWindow() {
        let selfBundleID = Bundle.main.bundleIdentifier
        let previousApp: NSRunningApplication? = DispatchQueue.main.sync {
            let front = NSWorkspace.shared.frontmostApplication
            _ = switchToKorean()
            showTemporaryInputWindowOnMain()
            if front?.bundleIdentifier != selfBundleID {
                return front
            }
            return nil
        }

        usleep(85_000)

        DispatchQueue.main.sync {
            hideTemporaryInputWindowOnMain()
            if let prev = previousApp {
                _ = prev.activate(options: [])
            }
        }

        let selfPID = ProcessInfo.processInfo.processIdentifier
        for _ in 0..<15 {
            let frontPID = DispatchQueue.main.sync {
                NSWorkspace.shared.frontmostApplication?.processIdentifier
            }
            if let frontPID, frontPID != selfPID {
                break
            }
            usleep(10_000)
        }

        DispatchQueue.main.sync {
            if !isKoreanActive() {
                _ = switchToKorean()
            }
        }
        usleep(15_000)
    }

    private static func showTemporaryInputWindowOnMain() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let size = NSSize(width: 3, height: 3)
        let rect = NSRect(
            x: frame.maxX - size.width - 8,
            y: frame.minY + 8,
            width: size.width,
            height: size.height
        )
        let win: TemporaryInputWindow
        if let existing = temporaryWindow {
            existing.setFrame(rect, display: false)
            win = existing
        } else {
            let created = TemporaryInputWindow(
                contentRect: rect,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            created.isReleasedWhenClosed = false
            created.isOpaque = false
            created.backgroundColor = .clear
            created.alphaValue = 0.01
            created.hasShadow = false
            created.ignoresMouseEvents = true
            created.level = .screenSaver
            created.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            created.contentView = NSTextView(frame: NSRect(origin: .zero, size: size))
            temporaryWindow = created
            win = created
        }

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let textView = win.contentView {
            win.makeFirstResponder(textView)
        }
    }

    private static func hideTemporaryInputWindowOnMain() {
        guard let win = temporaryWindow else { return }
        win.orderOut(nil)
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

// MARK: - Keys Held Back During a Replacement

/// Modifier key codes: Right Cmd, Cmd, Shift, Caps Lock, Opt, Ctrl, Right Shift, Right Opt,
/// Right Ctrl, Fn.
fileprivate func isModifierKeyCode(_ keyCode: CGKeyCode) -> Bool {
    return (54...63).contains(Int(keyCode))
}

/// A user keystroke held back while a replacement runs, to be replayed afterwards.
struct DeferredUserKey: Equatable {
    let keyCode: CGKeyCode
    /// Shift/Ctrl/Opt/Cmd/Fn only. An unmodified key carries none.
    let modifiers: CGEventFlags

    /// A Cmd/Ctrl/Opt shortcut. It must reach the app as a modified key stroke.
    var isCombo: Bool {
        return !modifiers.intersection([.maskControl, .maskAlternate, .maskCommand]).isEmpty
    }

    /// The key to hold back while a replacement runs, or nil when the event passes straight through.
    ///
    /// Plain keys wait so the next word starts in the new input source. Ctrl shortcuts wait only
    /// while the Ctrl-combo switch is on, so a shortcut typed after the triggering combo cannot
    /// overtake it. Cmd and Opt shortcuts and modifier keys are never held.
    static func held(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        ctrlComboSwitchEnabled: Bool
    ) -> DeferredUserKey? {
        guard !isModifierKeyCode(keyCode) else { return nil }
        let key = DeferredUserKey(keyCode: keyCode, modifiers: InputSourceManager.keyStrokeModifiers(of: flags))
        if key.isCombo {
            guard ctrlComboSwitchEnabled, key.modifiers.contains(.maskControl) else { return nil }
        }
        return key
    }
}

/// Keys typed during a replacement, in press order.
struct DeferredKeyQueue {
    static let cap = 16

    private(set) var keys: [DeferredUserKey] = []

    mutating func enqueue(_ key: DeferredUserKey) {
        guard keys.count < Self.cap else { return }
        keys.append(key)
    }

    mutating func removeAll() {
        keys.removeAll()
    }

    mutating func takeAll() -> [DeferredUserKey] {
        let taken = keys
        keys.removeAll()
        return taken
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

    var switchToEnglishOnCtrlCombo: Bool = true {
        didSet {
            UserDefaults.standard.set(switchToEnglishOnCtrlCombo, forKey: "switchToEnglishOnCtrlCombo")
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

    private let stateLock = NSLock()
    private var isReplacingStorage: Bool = false
    private var deferredUserKeys = DeferredKeyQueue()
    private var ignoreSourceChangeNotificationsUntil: TimeInterval = 0
    private var sourceChangeObserverInstalled: Bool = false
    private let selfPID: Int64 = Int64(ProcessInfo.processInfo.processIdentifier)

    private var isReplacing: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isReplacingStorage
    }

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
        if UserDefaults.standard.object(forKey: "switchToEnglishOnCtrlCombo") != nil {
            switchToEnglishOnCtrlCombo = UserDefaults.standard.bool(forKey: "switchToEnglishOnCtrlCombo")
        }
        learnedList = LearnedEnToKoList.loadFromDefaults()
    }

    /// Starts a replacement. `replayAfter` is queued first, so a combo the tap swallowed on
    /// purpose is delivered before any key typed after it.
    fileprivate func beginReplacing(replayAfter: [DeferredUserKey] = []) {
        stateLock.lock()
        isReplacingStorage = true
        deferredUserKeys.removeAll()
        for key in replayAfter {
            deferredUserKeys.enqueue(key)
        }
        ignoreSourceChangeNotificationsUntil = ProcessInfo.processInfo.systemUptime + 0.6
        stateLock.unlock()
    }

    /// Holds a keystroke while a replacement runs, and returns true so the event is swallowed.
    /// False when no replacement is running. The check and the enqueue share one lock hold, so a
    /// key cannot land in the queue after the worker has drained it.
    fileprivate func holdKeyWhileReplacing(_ key: DeferredUserKey) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard isReplacingStorage else { return false }
        deferredUserKeys.enqueue(key)
        return true
    }

    fileprivate func finishReplacingAndTakeDeferredKeys() -> [DeferredUserKey] {
        stateLock.lock()
        isReplacingStorage = false
        ignoreSourceChangeNotificationsUntil = ProcessInfo.processInfo.systemUptime + 0.35
        let queued = deferredUserKeys.takeAll()
        stateLock.unlock()
        return queued
    }

    private func shouldHandleExternalSourceChange() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !isReplacingStorage && ProcessInfo.processInfo.systemUptime >= ignoreSourceChangeNotificationsUntil
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
        installSourceChangeObserverIfNeeded()
        return true
    }

    private func installSourceChangeObserverIfNeeded() {
        guard !sourceChangeObserverInstalled else { return }
        sourceChangeObserverInstalled = true
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.shouldHandleExternalSourceChange() else { return }
            self.buffer.reset()
            self.currentPrefixSymbol = nil
            self.lastWordBeforeSpace = nil
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let userData = event.getIntegerValueField(.eventSourceUserData)
        // Ignore our own synthetic events
        if userData == SELF_EVENT_TAG {
            return Unmanaged.passRetained(event)
        }
        if userData != REPLAY_EVENT_TAG &&
           isReplacing &&
           event.getIntegerValueField(.eventSourceUnixProcessID) == selfPID {
            return Unmanaged.passRetained(event)
        }

        guard isEnabled else {
            return Unmanaged.passRetained(event)
        }

        // While replacing & switching input sources, hold fast follow-up keystrokes and replay
        // them once the target input language is active so the next word starts in the new language.
        // The hold checks and enqueues under one lock hold: a key must not land in the queue after
        // the worker drained it.
        if type == .keyDown,
           let held = DeferredUserKey.held(
               keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
               flags: event.flags,
               ctrlComboSwitchEnabled: switchToEnglishOnCtrlCombo
           ),
           holdKeyWhileReplacing(held) {
            return nil
        }
        if isReplacing {
            if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
                resetTracking()
            }
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

        // Ctrl combo in Korean mode: switch to English first, then deliver the combo to the app
        if hasCtrl && !isModifierKeyCode(keyCode) && switchToEnglishOnCtrlCombo && InputSourceManager.isKoreanActive() {
            return handleCtrlCombo(keyCode: keyCode, flags: flags, originalEvent: event)
        }

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

        // Quote (keyCode 39): `'` unshifted, `"` with Shift
        if keyCode == 39 {
            return handleQuoteKey(inKorean: inKorean, quote: hasShift ? "\"" : "'", originalEvent: event)
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

        // Case 3: Buffer is empty -> reliably toggle Korean/English IME
        performInputSourceToggle(currentlyKorean: inKorean)
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
        if autoConvertWord(sim, inKorean: inKorean, terminator: " ") {
            return nil // Suppress original Space; our replacement appends " "
        }

        // Not auto-converted: remember this word in case the user presses Shift+Space right after Space!
        lastWordBeforeSpace = (sim: sim, wasKorean: inKorean)
        return Unmanaged.passRetained(originalEvent)
    }

    /// A closing `'` or `"` ends the word like Space does ("tlgja" -> "시험").
    private func handleQuoteKey(inKorean: Bool, quote: String, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        cancelPendingEnToKoUndo()
        lastWordBeforeSpace = nil
        guard !buffer.isEmpty else {
            resetTracking()
            return Unmanaged.passRetained(originalEvent)
        }
        let sim = buffer.snapshot()
        if autoConvertWord(sim, inKorean: inKorean, terminator: quote) {
            return nil // Suppress original quote; our replacement appends it
        }
        resetTracking()
        return Unmanaged.passRetained(originalEvent)
    }

    /// Clears the word buffer and, when the word is a typo, replaces it plus `terminator`.
    /// Returns true when the replacement was posted and the original key must be swallowed.
    private func autoConvertWord(_ sim: SimulationResult, inKorean: Bool, terminator: String) -> Bool {
        let prefix = currentPrefixSymbol
        buffer.reset()
        currentPrefixSymbol = nil

        if inKorean && TypoDetector.shouldAutoConvertKoToEn(sim: sim, mode: mode, prefixSymbol: prefix) {
            lastWordBeforeSpace = nil
            performReplacement(
                deleteCount: sim.backspacesInKoreanComposing,
                switchToKorean: false,
                insertText: sim.englishText + terminator,
                fromLabel: sim.koreanText,
                toLabel: sim.englishText
            )
            return true
        }

        if !inKorean && TypoDetector.shouldAutoConvertEnToKo(
            sim: sim,
            mode: mode,
            learned: learnedList.lookup(sim.englishText)
        ) {
            lastWordBeforeSpace = nil
            // Korean syllables plus the trailing terminator we insert.
            pendingEnToKoUndo = PendingEnToKoUndo(
                english: sim.englishText,
                insertedCharacterCount: sim.koreanText.count + terminator.count
            )
            performReplacement(
                deleteCount: sim.backspacesInEnglish,
                switchToKorean: true,
                insertText: sim.koreanText + terminator,
                fromLabel: sim.englishText,
                toLabel: sim.koreanText
            )
            return true
        }
        return false
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

    /// A Ctrl combo arrived in Korean mode. Switch the input source to English, converting the
    /// pending word when Space would convert it, then deliver the combo once English is active.
    private func handleCtrlCombo(keyCode: CGKeyCode, flags: CGEventFlags, originalEvent: CGEvent) -> Unmanaged<CGEvent>? {
        let modifiers = InputSourceManager.shortcutModifiers(of: flags)
        let action = TypoDetector.ctrlComboAction(
            isInputSourceSwitchHotKey: InputSourceManager.matchesInputSourceSwitchHotKey(
                keyCode: keyCode,
                modifiers: modifiers,
                hotKeys: InputSourceManager.inputSourceSwitchHotKeys()
            ),
            sim: buffer.isEmpty ? nil : buffer.snapshot(),
            mode: mode,
            prefixSymbol: currentPrefixSymbol
        )
        if case .passThrough = action {
            resetTracking()
            return Unmanaged.passRetained(originalEvent)
        }

        // Fn rides along with the combo: Ctrl+Fn+Left must not come back as Ctrl+Left.
        let combo = DeferredUserKey(keyCode: keyCode, modifiers: InputSourceManager.keyStrokeModifiers(of: flags))
        resetTracking()
        switch action {
        case .convertWord(let sim):
            performReplacement(
                deleteCount: sim.backspacesInKoreanComposing,
                switchToKorean: false,
                insertText: sim.englishText,
                fromLabel: sim.koreanText,
                toLabel: sim.englishText,
                replayAfter: [combo]
            )
        case .switchInputSource:
            performInputSourceToggle(currentlyKorean: true, replayAfter: [combo])
        case .passThrough:
            break
        }
        return nil // Consume the combo; it is replayed once English is active
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
    private func performInputSourceToggle(currentlyKorean: Bool, replayAfter: [DeferredUserKey] = []) {
        beginReplacing(replayAfter: replayAfter)
        workerQueue.async { [weak self] in
            if currentlyKorean {
                InputSourceManager.activateEnglishFromWorker(postShortcut: { Self.postSymbolicHotKey($0) })
            } else {
                InputSourceManager.activateKoreanFromWorker(postShortcut: { Self.postSymbolicHotKey($0) })
            }
            self?.completeReplacingAndReplay()
        }
    }

    private func performReplacement(
        deleteCount: Int,
        switchToKorean: Bool,
        insertText: String,
        fromLabel: String,
        toLabel: String,
        replayAfter: [DeferredUserKey] = []
    ) {
        beginReplacing(replayAfter: replayAfter)
        recordConversion(from: fromLabel, to: toLabel)

        workerQueue.async { [weak self] in
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

                // Phase 3: Activate Korean in the focused app's TSMDocument (not just the menu-bar icon)
                InputSourceManager.activateKoreanFromWorker(postShortcut: { Self.postSymbolicHotKey($0) })
            } else {
                // Direction: Korean -> English
                // Phase 2: Switch IME to English (ABC) first so KoreanIM deactivates before English text arrives
                InputSourceManager.activateEnglishFromWorker(postShortcut: { Self.postSymbolicHotKey($0) })

                // Phase 3: Inject English text now that ABC is active
                Self.postUnicodeString(insertText, source: src)
            }

            self?.completeReplacingAndReplay()
        }
    }

    private func completeReplacingAndReplay() {
        usleep(10_000)
        let queued = finishReplacingAndTakeDeferredKeys()
        guard !queued.isEmpty else { return }
        for key in queued {
            Self.postReplayedUserKey(key)
        }
    }

    private static func modifierKeyCodes(for flags: CGEventFlags) -> [CGKeyCode] {
        var codes: [CGKeyCode] = []
        if flags.contains(.maskControl)   { codes.append(59) } // kVK_Control
        if flags.contains(.maskAlternate) { codes.append(58) } // kVK_Option
        if flags.contains(.maskShift)     { codes.append(56) } // kVK_Shift
        if flags.contains(.maskCommand)   { codes.append(55) } // kVK_Command
        return codes
    }

    /// Synthesizes a full hardware-level modifier + key + modifier-release sequence for a macOS SymbolicHotKey.
    /// Preserves native `NX_DEVICE*` modifier bits so `TextInputMenuAgent` immediately commits without leaving HUD open.
    ///
    /// `excludingHeldModifiers` is for a combo the tap is replaying for the user: the key itself
    /// then carries only the combo's modifiers, so a Shift pressed in the meantime cannot turn
    /// Ctrl+P into Ctrl+Shift+P. The modifier key events still report the keyboard as it is.
    private static func postSymbolicHotKey(
        _ hotKey: InputSourceManager.SymbolicHotKey,
        excludingHeldModifiers: Bool = false
    ) {
        let src = CGEventSource(stateID: .hidSystemState)
        let modCodes = modifierKeyCodes(for: hotKey.modifiers)
        guard !modCodes.isEmpty else { return }

        var activeFlags: CGEventFlags = []
        var prefixFlags: [CGEventFlags] = []

        for modCode in modCodes {
            prefixFlags.append(activeFlags)
            guard let modDown = CGEvent(keyboardEventSource: src, virtualKey: modCode, keyDown: true) else {
                continue
            }
            activeFlags.formUnion(modDown.flags)
            modDown.flags = activeFlags
            modDown.setIntegerValueField(.eventSourceUserData, value: SELF_EVENT_TAG)
            modDown.post(tap: .cghidEventTap)
            usleep(4_000)
        }

        if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: hotKey.keyCode, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: src, virtualKey: hotKey.keyCode, keyDown: false) {
            let keyFlags = excludingHeldModifiers
                ? InputSourceManager.keyStrokeFlags(from: activeFlags, modifiers: hotKey.modifiers)
                : activeFlags
            keyDown.flags = keyFlags
            keyUp.flags = keyFlags
            keyDown.setIntegerValueField(.eventSourceUserData, value: SELF_EVENT_TAG)
            keyUp.setIntegerValueField(.eventSourceUserData, value: SELF_EVENT_TAG)
            keyDown.post(tap: .cghidEventTap)
            usleep(4_000)
            keyUp.post(tap: .cghidEventTap)
            usleep(4_000)
        }

        for (idx, modCode) in modCodes.enumerated().reversed() {
            guard let modUp = CGEvent(keyboardEventSource: src, virtualKey: modCode, keyDown: false) else {
                continue
            }
            if idx > 0 {
                modUp.flags = prefixFlags[idx]
            }
            modUp.setIntegerValueField(.eventSourceUserData, value: SELF_EVENT_TAG)
            modUp.post(tap: .cghidEventTap)
            usleep(2_500)
        }
    }

    /// Replays a key held back during a replacement.
    ///
    /// A combo goes out as the same modifier + key sequence as the input-source shortcut, so
    /// system shortcuts such as desktop switching see what a real key press looks like. The key
    /// carries only the combo's own modifiers. It is tagged as ours, so the tap passes it on
    /// without switching the input source again.
    private static func postReplayedUserKey(_ key: DeferredUserKey) {
        if key.isCombo {
            postSymbolicHotKey(
                InputSourceManager.SymbolicHotKey(keyCode: key.keyCode, modifiers: key.modifiers),
                excludingHeldModifiers: true
            )
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        if key.modifiers.contains(.maskShift) {
            let shiftDown = CGEvent(keyboardEventSource: src, virtualKey: 56, keyDown: true)
            let shiftFlags = shiftDown?.flags ?? [.maskShift]
            if let shiftDown {
                shiftDown.setIntegerValueField(.eventSourceUserData, value: SELF_EVENT_TAG)
                shiftDown.post(tap: .cghidEventTap)
                usleep(2_000)
            }
            if let down = CGEvent(keyboardEventSource: src, virtualKey: key.keyCode, keyDown: true),
               let up = CGEvent(keyboardEventSource: src, virtualKey: key.keyCode, keyDown: false) {
                down.flags = shiftFlags
                up.flags = shiftFlags
                down.setIntegerValueField(.eventSourceUserData, value: REPLAY_EVENT_TAG)
                up.setIntegerValueField(.eventSourceUserData, value: REPLAY_EVENT_TAG)
                down.post(tap: .cghidEventTap)
                usleep(2_000)
                up.post(tap: .cghidEventTap)
                usleep(2_000)
            }
            if let shiftUp = CGEvent(keyboardEventSource: src, virtualKey: 56, keyDown: false) {
                shiftUp.setIntegerValueField(.eventSourceUserData, value: SELF_EVENT_TAG)
                shiftUp.post(tap: .cghidEventTap)
                usleep(2_000)
            }
        } else {
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: key.keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: key.keyCode, keyDown: false) else {
                return
            }
            down.flags = []
            up.flags = []
            down.setIntegerValueField(.eventSourceUserData, value: REPLAY_EVENT_TAG)
            up.setIntegerValueField(.eventSourceUserData, value: REPLAY_EVENT_TAG)
            down.post(tap: .cghidEventTap)
            usleep(2_000)
            up.post(tap: .cghidEventTap)
            usleep(2_500)
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

        let ctrlComboItem = NSMenuItem(
            title: "Ctrl 조합키 입력 시 한글 → 영문 전환",
            action: #selector(toggleCtrlComboSwitch),
            keyEquivalent: ""
        )
        ctrlComboItem.target = self
        ctrlComboItem.state = engine.switchToEnglishOnCtrlCombo ? .on : .off
        menu.addItem(ctrlComboItem)

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

    @objc private func toggleCtrlComboSwitch() {
        KoEnFixEngine.shared.switchToEnglishOnCtrlCombo.toggle()
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

    // 6. Symbolic hotkey parsing & input source classification tests
    do {
        let hotKeys: [String: Any] = [
            "60": [
                "enabled": true,
                "value": [
                    "parameters": [32, 49, 262144],
                    "type": "standard"
                ]
            ],
            "61": [
                "enabled": false,
                "value": [
                    "parameters": [32, 49, 786432],
                    "type": "standard"
                ]
            ],
            "invalidKeyCode": [
                "enabled": true,
                "value": [
                    "parameters": [65535, 65535, 262144],
                    "type": "standard"
                ]
            ]
        ]

        let parsed60 = InputSourceManager.parseSymbolicHotKey(from: hotKeys, id: "60")
        expect(
            parsed60 == InputSourceManager.SymbolicHotKey(keyCode: 49, modifiers: [.maskControl]),
            "SymbolicHotKey 60 parses Ctrl+Space (keyCode 49, .maskControl)"
        )
        expect(
            InputSourceManager.parseSymbolicHotKey(from: hotKeys, id: "61") == nil,
            "Disabled SymbolicHotKey 61 returns nil"
        )
        expect(
            InputSourceManager.parseSymbolicHotKey(from: hotKeys, id: "invalidKeyCode") == nil,
            "Out-of-range keyCode 65535 returns nil"
        )

        let ctrlOptFlags = InputSourceManager.convertCarbonModifiersToCGFlags(786432)
        expect(
            ctrlOptFlags == [.maskControl, .maskAlternate],
            "Carbon modifier 786432 maps to [.maskControl, .maskAlternate]"
        )

        expect(InputSourceManager.isKoreanSourceID("com.apple.inputmethod.Korean.2SetKorean"), "2SetKorean is recognized as Korean")
        expect(!InputSourceManager.isKoreanSourceID("com.apple.keylayout.ABC"), "ABC is recognized as non-Korean")
    }

    // 7. Ctrl combo in Korean mode converts the pending word when Space would, else only switches.
    do {
        func simulated(_ en: String) -> SimulationResult {
            HangulAutomata.simulate(HangulAutomata.strokes(fromEnglish: en)!)
        }
        func action(
            _ en: String,
            hotKey: Bool = false,
            mode: AutoConvertMode = .conservative,
            prefix: Character? = nil
        ) -> CtrlComboAction {
            TypoDetector.ctrlComboAction(
                isInputSourceSwitchHotKey: hotKey,
                sim: simulated(en),
                mode: mode,
                prefixSymbol: prefix
            )
        }
        for (en, ko) in [("ls", "ㅣㄴ"), ("tmux", "스ㅕㅌ"), ("git", "햣")] {
            expect(
                action(en) == .convertWord(simulated(en)),
                "Ctrl combo after the English typo '\(ko)' converts it to '\(en)'"
            )
            expect(
                action(en, mode: .aggressive) == .convertWord(simulated(en)),
                "Aggressive mode also converts '\(ko)' on a Ctrl combo"
            )
            expect(
                action(en, mode: .manualOnly) == .switchInputSource,
                "Manual mode leaves '\(ko)' as typed and only switches the input source"
            )
        }
        expect(
            action("q", prefix: ":") == .convertWord(simulated("q")),
            "Ctrl combo after ':ㅂ' converts the Vim command 'q'"
        )
        expect(
            action("la", prefix: "-") == .convertWord(simulated("la")),
            "Ctrl combo after '-ㅣㅁ' converts the CLI flag 'la'"
        )
        for (en, ko) in [("dkssud", "안녕"), ("go", "해")] {
            expect(
                action(en) == .switchInputSource,
                "Ctrl combo after the real Korean word '\(ko)' only switches the input source"
            )
        }
        expect(
            TypoDetector.ctrlComboAction(
                isInputSourceSwitchHotKey: false, sim: nil, mode: .conservative, prefixSymbol: nil
            ) == .switchInputSource,
            "Ctrl combo with no pending word only switches the input source"
        )
        expect(
            action("ls", hotKey: true) == .passThrough,
            "Ctrl+Space stays with the system input-source shortcut"
        )
    }

    // 8. Only the system's own input-source shortcuts (60, 61) are left to the system.
    do {
        let hotKeys: [String: Any] = [
            "60": [
                "enabled": true,
                "value": [
                    "parameters": [32, 49, 262144],
                    "type": "standard"
                ]
            ],
            "61": [
                "enabled": true,
                "value": [
                    "parameters": [32, 49, 786432],
                    "type": "standard"
                ]
            ],
            "118": [
                "enabled": true,
                "value": [
                    "parameters": [65535, 18, 262144],
                    "type": "standard"
                ]
            ]
        ]
        let switchHotKeys = InputSourceManager.inputSourceSwitchHotKeys(from: hotKeys)
        expect(switchHotKeys.count == 2, "Shortcuts 60 and 61 are the input-source shortcuts; 118 is not")
        expect(
            InputSourceManager.matchesInputSourceSwitchHotKey(keyCode: 49, modifiers: [.maskControl], hotKeys: switchHotKeys),
            "Ctrl+Space matches shortcut 60"
        )
        expect(
            InputSourceManager.matchesInputSourceSwitchHotKey(keyCode: 49, modifiers: [.maskControl, .maskAlternate], hotKeys: switchHotKeys),
            "Ctrl+Opt+Space matches shortcut 61"
        )
        expect(
            !InputSourceManager.matchesInputSourceSwitchHotKey(keyCode: 49, modifiers: [.maskControl, .maskShift], hotKeys: switchHotKeys),
            "Ctrl+Shift+Space is not an input-source shortcut"
        )
        expect(
            !InputSourceManager.matchesInputSourceSwitchHotKey(keyCode: 18, modifiers: [.maskControl], hotKeys: switchHotKeys),
            "Ctrl+1 is not an input-source shortcut"
        )
        expect(
            InputSourceManager.inputSourceSwitchHotKeys(from: ["61": ["enabled": false]]).isEmpty,
            "A disabled shortcut is ignored"
        )
        let physicalCtrl = InputSourceManager.convertCarbonModifiersToCGFlags(262144)
            .union(CGEventFlags(rawValue: 0x0101))
        expect(
            InputSourceManager.shortcutModifiers(of: physicalCtrl) == [.maskControl],
            "Device-dependent modifier bits are dropped"
        )
        let ctrlShiftHeld = InputSourceManager.convertCarbonModifiersToCGFlags(262144 | 131072)
            .union(CGEventFlags(rawValue: 0x0103))
        expect(
            InputSourceManager.keyStrokeFlags(from: ctrlShiftHeld, modifiers: [.maskControl])
                == CGEventFlags.maskControl.union(CGEventFlags(rawValue: 0x0101)),
            "Shift pressed after the combo is dropped from a replayed Ctrl combo, key and device bits alike"
        )
        expect(
            InputSourceManager.keyStrokeFlags(from: ctrlShiftHeld, modifiers: [.maskControl, .maskShift]) == ctrlShiftHeld,
            "Modifiers that belong to the combo are kept"
        )
        expect(
            InputSourceManager.keyStrokeFlags(from: [.maskAlternate, .maskCommand], modifiers: []) == [],
            "Every modifier can be dropped"
        )
        expect(
            InputSourceManager.keyStrokeFlags(from: [.maskControl], modifiers: [.maskControl, .maskSecondaryFn])
                == CGEventFlags.maskControl.union(.maskSecondaryFn),
            "A combo's Fn survives even when the user has already released it"
        )
        expect(
            InputSourceManager.keyStrokeFlags(from: [.maskControl, .maskSecondaryFn], modifiers: [.maskControl])
                == [.maskControl],
            "Fn pressed after the combo is dropped from the replayed key"
        )
        for (modifier, deviceBits) in [
            (CGEventFlags.maskControl, CGEventFlags(rawValue: 0x2001)),
            (CGEventFlags.maskAlternate, CGEventFlags(rawValue: 0x0060)),
            (CGEventFlags.maskCommand, CGEventFlags(rawValue: 0x0018))
        ] {
            let withDeviceBits = modifier.union(deviceBits)
            expect(
                InputSourceManager.keyStrokeFlags(from: withDeviceBits, modifiers: modifier) == withDeviceBits,
                "The device bits of modifier \(modifier.rawValue) are kept"
            )
        }
        expect(
            InputSourceManager.keyStrokeModifiers(of: [.maskControl, .maskSecondaryFn, CGEventFlags(rawValue: 0x0101)])
                == CGEventFlags.maskControl.union(.maskSecondaryFn),
            "A held key keeps Fn and loses device bits"
        )
    }

    // 9. Keys typed during a replacement: what waits, and the order it comes out in.
    do {
        let ctrl = InputSourceManager.convertCarbonModifiersToCGFlags(262144)
        let ctrlOpt = InputSourceManager.convertCarbonModifiersToCGFlags(786432)
        let cmd = InputSourceManager.convertCarbonModifiersToCGFlags(1048576)
        let opt = InputSourceManager.convertCarbonModifiersToCGFlags(524288)

        expect(
            DeferredUserKey.held(keyCode: 2, flags: [], ctrlComboSwitchEnabled: false) == DeferredUserKey(keyCode: 2, modifiers: []),
            "A plain key waits for the new input source"
        )
        expect(
            DeferredUserKey.held(keyCode: 2, flags: [.maskShift], ctrlComboSwitchEnabled: false) == DeferredUserKey(keyCode: 2, modifiers: [.maskShift]),
            "Shift+key waits for the new input source"
        )
        expect(
            DeferredUserKey.held(keyCode: 32, flags: ctrl, ctrlComboSwitchEnabled: true) == DeferredUserKey(keyCode: 32, modifiers: [.maskControl]),
            "With the Ctrl-combo switch on, a Ctrl combo waits behind the combo that triggered the replacement"
        )
        expect(
            DeferredUserKey.held(keyCode: 32, flags: ctrl, ctrlComboSwitchEnabled: false) == nil,
            "With the switch off, a Ctrl combo passes straight through"
        )
        let shift = InputSourceManager.convertCarbonModifiersToCGFlags(131072)
        for (name, extra) in [("Shift", shift), ("Opt", opt), ("Cmd", cmd)] {
            expect(
                DeferredUserKey.held(
                    keyCode: 44,
                    flags: ctrl.union(extra).union(CGEventFlags(rawValue: 0x0009)),
                    ctrlComboSwitchEnabled: true
                ) == DeferredUserKey(keyCode: 44, modifiers: CGEventFlags.maskControl.union(extra)),
                "Ctrl+\(name)+key waits with both modifiers kept and device bits dropped"
            )
            expect(
                DeferredUserKey.held(keyCode: 44, flags: ctrl.union(extra), ctrlComboSwitchEnabled: false) == nil,
                "With the switch off, Ctrl+\(name)+key passes straight through"
            )
        }
        expect(
            DeferredUserKey.held(
                keyCode: 123,
                flags: ctrl.union(.maskSecondaryFn),
                ctrlComboSwitchEnabled: true
            ) == DeferredUserKey(keyCode: 123, modifiers: [.maskControl, .maskSecondaryFn]),
            "Ctrl+Fn+arrow waits with Fn kept, so it is not replayed as a plain arrow"
        )
        expect(DeferredUserKey.held(keyCode: 8, flags: cmd, ctrlComboSwitchEnabled: true) == nil, "A Cmd shortcut is never held")
        expect(DeferredUserKey.held(keyCode: 8, flags: opt, ctrlComboSwitchEnabled: true) == nil, "An Opt shortcut is never held")
        expect(DeferredUserKey.held(keyCode: 59, flags: ctrl, ctrlComboSwitchEnabled: true) == nil, "A modifier key is never held")

        expect(DeferredUserKey(keyCode: 32, modifiers: [.maskControl]).isCombo, "A Ctrl combo is a combo")
        expect(DeferredUserKey(keyCode: 8, modifiers: ctrlOpt.union(cmd)).isCombo, "Ctrl+Opt+Cmd is a combo")
        expect(!DeferredUserKey(keyCode: 2, modifiers: [.maskShift]).isCombo, "Shift+key is not a combo")

        var queue = DeferredKeyQueue()
        queue.enqueue(DeferredUserKey(keyCode: 32, modifiers: [.maskControl]))
        queue.enqueue(DeferredUserKey(keyCode: 2, modifiers: []))
        queue.enqueue(DeferredUserKey(keyCode: 13, modifiers: [.maskControl]))
        expect(queue.keys.map { $0.keyCode } == [32, 2, 13], "Held keys keep press order")
        for code in 0..<20 {
            queue.enqueue(DeferredUserKey(keyCode: CGKeyCode(code), modifiers: []))
        }
        expect(queue.keys.count == DeferredKeyQueue.cap, "At most \(DeferredKeyQueue.cap) keys are held")
        expect(queue.keys.prefix(3).map { $0.keyCode } == [32, 2, 13], "The earliest keys, the triggering combo first, are kept")
        queue.removeAll()
        expect(queue.keys.isEmpty, "removeAll empties the queue")
        queue.enqueue(DeferredUserKey(keyCode: 5, modifiers: []))
        let taken = queue.takeAll()
        expect(taken.map { $0.keyCode } == [5] && queue.keys.isEmpty, "takeAll hands over everything once")
    }

    // 10. The engine holds keys across a replacement and replays the triggering combo first.
    do {
        let engine = KoEnFixEngine.shared
        let combo = DeferredUserKey(keyCode: 32, modifiers: [.maskControl])
        let typed = DeferredUserKey(keyCode: 2, modifiers: [])
        let shifted = DeferredUserKey(keyCode: 5, modifiers: [.maskShift])

        expect(!engine.holdKeyWhileReplacing(typed), "Outside a replacement no key is held")

        engine.beginReplacing(replayAfter: [combo])
        expect(engine.holdKeyWhileReplacing(typed), "A key typed during a replacement is held")
        expect(engine.holdKeyWhileReplacing(shifted), "A Shift+key typed during a replacement is held")
        expect(
            engine.finishReplacingAndTakeDeferredKeys() == [combo, typed, shifted],
            "The triggering combo is replayed first, then the later keys in press order"
        )

        expect(!engine.holdKeyWhileReplacing(typed), "Once the replacement ends no key is held")
        engine.beginReplacing()
        expect(engine.finishReplacingAndTakeDeferredKeys().isEmpty, "A replacement without a trigger replays nothing")
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
