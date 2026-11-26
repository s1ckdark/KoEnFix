# Ctrl Combo Korean → English Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a Ctrl combo arrives in Korean mode, KoEnFix switches the input source to `ABC` first (converting the pending English typo when `Space` would), then delivers the combo to the app.

**Architecture:** The tap's shortcut branch gains one new path: Ctrl combo in Korean mode → swallow → reuse the existing replacement sequencer or input-source toggle → replay the combo from the deferred key queue. The decision, the system-shortcut match and the deferral rule are pure functions fixed by self-tests.

**Tech Stack:** Swift, single file `Sources/KoEnFix.swift`; Cocoa + Carbon (`CGEvent` tap, TIS); the built-in `--self-test` harness.

**Spec:** `docs/superpowers/specs/2026-11-27-ctrl-combo-english-switch-design.md`

## Changes after the first code review

An independent review of the code commits `0074ced`..`0267f14` found no critical issue and three important ones. The tasks below are the plan as executed. These later commits changed the result, and the spec describes the final state:

- `9cbcf77`: the key events of a replayed combo carry only the combo's own modifiers, through `postSymbolicHotKey(_:excludingHeldModifiers:)`. So Task 4's text for `postReplayedUserKey` and Task 7's "j or g" follow-up are out of date; see the follow-up section. The helper it introduced was replaced in `cf8b6d8`.
- `cf8b6d8` (after a second review of the fixes above, which found no Critical or Important issue): a held key keeps Fn (`InputSourceManager.keyStrokeModifiers(of:)`), so Ctrl+Fn+Left is not replayed as Ctrl+Left. The replayed key's flags come from `InputSourceManager.keyStrokeFlags(from:modifiers:)`: the combo's own modifiers are always present, foreign modifiers and a foreign Fn are dropped. Task 3's `DeferredUserKey` doc comment is out of date.
- `19bad4d`: `holdKeyWhileReplacing` checks and enqueues under one lock hold, and `beginReplacing(replayAfter:)` queues the trigger while it clears the queue. Task 4's replacing branch, `enqueueDeferredUserKey` (since removed) and the two `replayAfter` loops in Task 5 are out of date.
- `1fc1585`: tests for Ctrl+Shift, Ctrl+Opt and Ctrl+Cmd combos and for the `-` prefix.
- The manual checklist in Task 7 gained rows k and l, and row g now uses two different shortcuts so that order is observable.

## Global Constraints

- Everything lives in `Sources/KoEnFix.swift`. The install script compiles that one file; no file splits, no new dependencies.
- macOS 13+ (`Package.swift`: `.macOS(.v13)`), swift-tools-version 5.9.
- Tests are `expect(...)` calls inside `runSelfTests()`, run with `--self-test`. There is no test target.
- Code comments are English; menu titles and README copy are Korean (existing convention).
- Scope is Ctrl combos only. Cmd-only and Opt-only combos keep passing straight through.
- `Ctrl+Space` and `Ctrl+Opt+Space` (symbolic hotkeys 60 and 61) are never triggers.
- A replayed combo uses the existing `postSymbolicHotKey` sequence (modifier down, key down/up, modifier up) and carries `SELF_EVENT_TAG`.
- **Do not touch the user's session.** Never launch KoEnFix, post `CGEvent`s, switch input sources, install, or open windows during implementation. Verification is compile plus `--self-test` only. Real-IME behavior is checked by the user from the checklist in Task 7.
- Never `git add -A`. `.mimosa/`, `.omc/`, `.video_agent/` are untracked tool directories and must stay out of commits.
- Commit messages: English, imperative subject, explanatory body (repo convention).

**Test command** (used in every task, about 2 seconds):

```bash
swiftc -Onone Sources/KoEnFix.swift -o /tmp/koenfix-selftest && /tmp/koenfix-selftest --self-test | grep -E "FAIL|passed|failed"
```

Expected when green: `🎉 All KoEnFix self-tests passed!` and no `FAIL` lines.

---

### Task 1: Decision function for a Ctrl combo

**Files:**
- Modify: `Sources/KoEnFix.swift` — top-level types (after the `AutoConvertMode` enum, line 29), `TypoDetector` (after `shouldAutoConvertKoToEn`, line 627), `runSelfTests()` (before `if failures == 0 {`, line 2383)

**Interfaces:**
- Consumes: `TypoDetector.shouldAutoConvertKoToEn(sim:mode:prefixSymbol:)`, `SimulationResult`
- Produces: `enum CtrlComboAction { case passThrough, switchInputSource, convertWord(SimulationResult) }`; `TypoDetector.ctrlComboAction(isInputSourceSwitchHotKey:sim:mode:prefixSymbol:) -> CtrlComboAction`

- [ ] **Step 1: Confirm the baseline is green**

Run: test command.
Expected: `🎉 All KoEnFix self-tests passed!`

- [ ] **Step 2: Write the failing test**

In `runSelfTests()`, insert this block between the end of test block `// 6. ...` (`}` on line 2381) and `if failures == 0 {`:

```swift
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
```

- [ ] **Step 3: Run the test to verify it fails**

Run: test command.
Expected: compile error `type 'TypoDetector' has no member 'ctrlComboAction'`.

- [ ] **Step 4: Add the action type**

After the closing brace of `enum AutoConvertMode` (line 29), before `struct KeyStroke`:

```swift
/// What KoEnFix does when a Ctrl combo arrives while a Korean input source is active.
enum CtrlComboAction: Equatable {
    /// A system input-source shortcut such as Ctrl+Space. The system handles it.
    case passThrough
    /// Leave the text alone and switch the input source to English.
    case switchInputSource
    /// Replace the pending English typo and switch the input source to English.
    case convertWord(SimulationResult)
}
```

- [ ] **Step 5: Add the decision function**

In `TypoDetector`, right after the closing brace of `shouldAutoConvertKoToEn` (line 627):

```swift
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
```

- [ ] **Step 6: Run the tests**

Run: test command.
Expected: green, including the new `Ctrl combo ...` PASS lines.

- [ ] **Step 7: Commit**

```bash
git add Sources/KoEnFix.swift
git commit -m "Decide what a Ctrl combo does in Korean mode." -m "The pending word converts when Space would convert it, a system input-source shortcut is left to the system, and everything else only switches the input source."
```

---

### Task 2: Match the system's input-source shortcuts

**Files:**
- Modify: `Sources/KoEnFix.swift` — `InputSourceManager` (after `parseSymbolicHotKey`, line 882), `runSelfTests()` (after test block 7)

**Interfaces:**
- Consumes: `InputSourceManager.parseSymbolicHotKey(from:id:)`, `InputSourceManager.SymbolicHotKey`
- Produces: `static func shortcutModifiers(of flags: CGEventFlags) -> CGEventFlags`; `static func inputSourceSwitchHotKeys(from hotKeys: [String: Any]) -> [SymbolicHotKey]`; `static func inputSourceSwitchHotKeys() -> [SymbolicHotKey]`; `static func matchesInputSourceSwitchHotKey(keyCode: CGKeyCode, modifiers: CGEventFlags, hotKeys: [SymbolicHotKey]) -> Bool`

- [ ] **Step 1: Write the failing test**

Insert after test block 7, before `if failures == 0 {`:

```swift
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
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: test command.
Expected: compile error `type 'InputSourceManager' has no member 'inputSourceSwitchHotKeys'`.

- [ ] **Step 3: Implement**

In `InputSourceManager`, right after the closing brace of `parseSymbolicHotKey` (line 882), before `static func previousInputSourceHotKey()`:

```swift
    /// The Shift/Ctrl/Opt/Cmd part of event flags. Device-dependent bits are dropped.
    static func shortcutModifiers(of flags: CGEventFlags) -> CGEventFlags {
        return flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
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
```

- [ ] **Step 4: Run the tests**

Run: test command.
Expected: green, including the new shortcut PASS lines.

- [ ] **Step 5: Commit**

```bash
git add Sources/KoEnFix.swift
git commit -m "Match the system's input-source shortcuts by key and modifiers." -m "Ctrl+Space and Ctrl+Opt+Space must stay with the system, so a Ctrl combo is compared against enabled symbolic hotkeys 60 and 61 before KoEnFix acts on it."
```

---

### Task 3: Deferred keys with modifiers

**Files:**
- Modify: `Sources/KoEnFix.swift` — new section before `// MARK: - Keyboard Event Injector & Tap Manager` (line 1155), `runSelfTests()` (after test block 8)

**Interfaces:**
- Consumes: `InputSourceManager.shortcutModifiers(of:)` (Task 2)
- Produces: `fileprivate func isModifierKeyCode(_ keyCode: CGKeyCode) -> Bool`; `struct DeferredUserKey: Equatable { let keyCode: CGKeyCode; let modifiers: CGEventFlags; var isCombo: Bool; static func held(keyCode: CGKeyCode, flags: CGEventFlags, ctrlComboSwitchEnabled: Bool) -> DeferredUserKey? }`; `struct DeferredKeyQueue { static let cap: Int; var keys: [DeferredUserKey]; mutating func enqueue(_:); mutating func removeAll(); mutating func takeAll() -> [DeferredUserKey] }`

- [ ] **Step 1: Write the failing test**

Insert after test block 8, before `if failures == 0 {`:

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: test command.
Expected: compile error `cannot find 'DeferredUserKey' in scope`.

- [ ] **Step 3: Implement**

Insert a new section immediately before `// MARK: - Keyboard Event Injector & Tap Manager` (line 1155):

```swift
// MARK: - Keys Held Back During a Replacement

/// Modifier key codes: Right Cmd, Cmd, Shift, Caps Lock, Opt, Ctrl, Right Shift, Right Opt,
/// Right Ctrl, Fn.
fileprivate func isModifierKeyCode(_ keyCode: CGKeyCode) -> Bool {
    return (54...63).contains(Int(keyCode))
}

/// A user keystroke held back while a replacement runs, to be replayed afterwards.
struct DeferredUserKey: Equatable {
    let keyCode: CGKeyCode
    /// Shift/Ctrl/Opt/Cmd only. An unmodified key carries none.
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
        let key = DeferredUserKey(keyCode: keyCode, modifiers: InputSourceManager.shortcutModifiers(of: flags))
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

```

- [ ] **Step 4: Run the tests**

Run: test command.
Expected: green, including the new `waits`, `never held` and `queue` PASS lines.

- [ ] **Step 5: Commit**

```bash
git add Sources/KoEnFix.swift
git commit -m "Hold Ctrl combos in the deferred key queue." -m "Deferred keys now keep their Shift/Ctrl/Opt/Cmd modifiers. Plain keys wait as before; a Ctrl combo waits only while the Ctrl-combo switch is on, so it cannot overtake the combo that triggered the replacement."
```

---

### Task 4: Feature flag and deferred queue wiring in the engine

This task is a behavior-preserving refactor for plain and Shift keys. It adds the flag the later tasks read, and teaches the replayer to send combos. There is no new unit test: the queue and the rule are covered by Task 3, and the engine glue is reviewed in Task 7.

**Files:**
- Modify: `Sources/KoEnFix.swift` — `KoEnFixEngine`: properties (line 1174), `init` (line 1210), state (line 1196), queue helpers (lines 1232–1248), `handleEvent` replacing branch (lines 1373–1391), `completeReplacingAndReplay` (line 1723), `postReplayedUserKey` (line 1788)

**Interfaces:**
- Consumes: `DeferredUserKey`, `DeferredKeyQueue`, `DeferredUserKey.held(keyCode:flags:ctrlComboSwitchEnabled:)` (Task 3)
- Produces: `var switchToEnglishOnCtrlCombo: Bool`; `private func enqueueDeferredUserKey(_ key: DeferredUserKey)`; `private func finishReplacingAndTakeDeferredKeys() -> [DeferredUserKey]`; `private static func postReplayedUserKey(_ key: DeferredUserKey)`

- [ ] **Step 1: Add the flag**

After the `convertOnTerminalEnter` property (line 1179):

```swift
    var switchToEnglishOnCtrlCombo: Bool = true {
        didSet {
            UserDefaults.standard.set(switchToEnglishOnCtrlCombo, forKey: "switchToEnglishOnCtrlCombo")
            onStateChange?()
        }
    }
```

In `init`, after the `convertOnTerminalEnter` load (line 1220):

```swift
        if UserDefaults.standard.object(forKey: "switchToEnglishOnCtrlCombo") != nil {
            switchToEnglishOnCtrlCombo = UserDefaults.standard.bool(forKey: "switchToEnglishOnCtrlCombo")
        }
```

- [ ] **Step 2: Switch the engine's queue to `DeferredKeyQueue`**

Replace the state line (1196):

```swift
    private var deferredUserKeys = DeferredKeyQueue()
```

Replace `enqueueDeferredUserKey` (lines 1232–1238):

```swift
    private func enqueueDeferredUserKey(_ key: DeferredUserKey) {
        stateLock.lock()
        deferredUserKeys.enqueue(key)
        stateLock.unlock()
    }
```

Replace `finishReplacingAndTakeDeferredKeys` (lines 1240–1248):

```swift
    private func finishReplacingAndTakeDeferredKeys() -> [DeferredUserKey] {
        stateLock.lock()
        isReplacingStorage = false
        ignoreSourceChangeNotificationsUntil = ProcessInfo.processInfo.systemUptime + 0.35
        let queued = deferredUserKeys.takeAll()
        stateLock.unlock()
        return queued
    }
```

`beginReplacing()` needs no change: it already calls `deferredUserKeys.removeAll()`.

- [ ] **Step 3: Route the replacing branch through `held`**

Replace the `if isReplacing { ... }` block in `handleEvent` (lines 1373–1391):

```swift
        // While replacing & switching input sources, hold fast follow-up keystrokes and replay
        // them once the target input language is active so the next word starts in the new language.
        if isReplacing {
            if type == .keyDown,
               let held = DeferredUserKey.held(
                   keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
                   flags: event.flags,
                   ctrlComboSwitchEnabled: switchToEnglishOnCtrlCombo
               ) {
                enqueueDeferredUserKey(held)
                return nil
            } else if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
                resetTracking()
            }
            return Unmanaged.passRetained(event)
        }
```

- [ ] **Step 4: Replay deferred keys by value**

Replace `completeReplacingAndReplay` (lines 1723–1730):

```swift
    private func completeReplacingAndReplay() {
        usleep(10_000)
        let queued = finishReplacingAndTakeDeferredKeys()
        guard !queued.isEmpty else { return }
        for key in queued {
            Self.postReplayedUserKey(key)
        }
    }
```

Replace the whole `postReplayedUserKey(keyCode:isShift:)` (lines 1788–1828):

```swift
    /// Replays a key held back during a replacement.
    ///
    /// A combo goes out as the same modifier + key sequence as the input-source shortcut, so
    /// system shortcuts such as desktop switching see what a real key press looks like. It is
    /// tagged as ours, so the tap passes it on without switching the input source again.
    private static func postReplayedUserKey(_ key: DeferredUserKey) {
        if key.isCombo {
            postSymbolicHotKey(InputSourceManager.SymbolicHotKey(keyCode: key.keyCode, modifiers: key.modifiers))
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
```

- [ ] **Step 5: Run the tests**

Run: test command.
Expected: green. The old code's last use of the `(keyCode:isShift:)` signature is gone, so the file must compile.

- [ ] **Step 6: Commit**

```bash
git add Sources/KoEnFix.swift
git commit -m "Replay deferred keys with their modifiers." -m "The engine keeps deferred keys in DeferredKeyQueue and decides what waits through DeferredUserKey.held. A held combo is replayed with the input-source shortcut's modifier sequence instead of being passed through mid-replacement."
```

---

### Task 5: The Ctrl-combo trigger

**Files:**
- Modify: `Sources/KoEnFix.swift` — `handleEvent` main path (lines 1403–1415, after Task 4 they sit about 15 lines later), new `handleCtrlCombo` after `handleEnterKey` (before `// MARK: - Deterministic Replacement Sequencer`), `performInputSourceToggle`, `performReplacement`

**Interfaces:**
- Consumes: `TypoDetector.ctrlComboAction` (Task 1), `InputSourceManager.inputSourceSwitchHotKeys()` and `matchesInputSourceSwitchHotKey` (Task 2), `isModifierKeyCode` and `DeferredUserKey` (Task 3), `switchToEnglishOnCtrlCombo` (Task 4)
- Produces: `private func handleCtrlCombo(keyCode: CGKeyCode, flags: CGEventFlags, originalEvent: CGEvent) -> Unmanaged<CGEvent>?`; `performInputSourceToggle(currentlyKorean:replayAfter:)`; `performReplacement(..., replayAfter: [DeferredUserKey] = [])`

- [ ] **Step 1: Add the trigger to the main path**

In `handleEvent`, replace the shortcut branch:

```swift
        // Any Cmd / Ctrl / Opt shortcut resets the buffer and passes through
        if hasCmd || hasCtrl || hasOpt {
            resetTracking()
            return Unmanaged.passRetained(event)
        }
```

with:

```swift
        // Ctrl combo in Korean mode: switch to English first, then deliver the combo to the app
        if hasCtrl && !isModifierKeyCode(keyCode) && switchToEnglishOnCtrlCombo && InputSourceManager.isKoreanActive() {
            return handleCtrlCombo(keyCode: keyCode, flags: flags, originalEvent: event)
        }

        // Any Cmd / Ctrl / Opt shortcut resets the buffer and passes through
        if hasCmd || hasCtrl || hasOpt {
            resetTracking()
            return Unmanaged.passRetained(event)
        }
```

- [ ] **Step 2: Add the handler**

After the closing brace of `handleEnterKey`, before `// MARK: - Deterministic Replacement Sequencer`:

```swift
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

        let combo = DeferredUserKey(keyCode: keyCode, modifiers: modifiers)
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
```

- [ ] **Step 3: Carry the combo through both performers**

Replace `performInputSourceToggle(currentlyKorean:)`:

```swift
    private func performInputSourceToggle(currentlyKorean: Bool, replayAfter: [DeferredUserKey] = []) {
        beginReplacing()
        for key in replayAfter {
            enqueueDeferredUserKey(key)
        }
        workerQueue.async { [weak self] in
            if currentlyKorean {
                InputSourceManager.activateEnglishFromWorker(postShortcut: Self.postSymbolicHotKey)
            } else {
                InputSourceManager.activateKoreanFromWorker(postShortcut: Self.postSymbolicHotKey)
            }
            self?.completeReplacingAndReplay()
        }
    }
```

In `performReplacement`, add the parameter and the enqueue loop. The signature becomes:

```swift
    private func performReplacement(
        deleteCount: Int,
        switchToKorean: Bool,
        insertText: String,
        fromLabel: String,
        toLabel: String,
        replayAfter: [DeferredUserKey] = []
    ) {
        beginReplacing()
        for key in replayAfter {
            enqueueDeferredUserKey(key)
        }
        recordConversion(from: fromLabel, to: toLabel)
```

The rest of `performReplacement` is unchanged.

- [ ] **Step 4: Run the tests**

Run: test command.
Expected: green.

- [ ] **Step 5: Commit**

```bash
git add Sources/KoEnFix.swift
git commit -m "Switch to English before delivering a Ctrl combo typed in Korean mode." -m "The tap holds a Ctrl combo that arrives in Korean mode, switches the input source to ABC (converting the pending word when Space would), then replays the combo. Ctrl+Space and Ctrl+Opt+Space still go straight to the system."
```

---

### Task 6: Menu toggle and README

**Files:**
- Modify: `Sources/KoEnFix.swift` — `rebuildMenu()` (line 2039), `toggleTerminalEnter` (line 2121)
- Modify: `README.md` — list under `## 주요 기능`

**Interfaces:**
- Consumes: `KoEnFixEngine.switchToEnglishOnCtrlCombo` (Task 4)
- Produces: menu item "Ctrl 조합키 입력 시 한글 → 영문 전환"

- [ ] **Step 1: Add the menu item**

In `rebuildMenu()`, directly after `menu.addItem(termEnterItem)` (line 2046), before the separator:

```swift
        let ctrlComboItem = NSMenuItem(
            title: "Ctrl 조합키 입력 시 한글 → 영문 전환",
            action: #selector(toggleCtrlComboSwitch),
            keyEquivalent: ""
        )
        ctrlComboItem.target = self
        ctrlComboItem.state = engine.switchToEnglishOnCtrlCombo ? .on : .off
        menu.addItem(ctrlComboItem)
```

Add the action next to `toggleTerminalEnter`:

```swift
    @objc private func toggleCtrlComboSwitch() {
        KoEnFixEngine.shared.switchToEnglishOnCtrlCombo.toggle()
    }
```

- [ ] **Step 2: Document the feature**

Append to the numbered list under `## 주요 기능` in `README.md`:

```markdown
5. **Ctrl 조합키 입력 시 한글 → 영문 전환**
   - 한글 모드에서 `Ctrl` 조합키(`Ctrl+P`, `Ctrl+U`, tmux 접두어 `Ctrl+B` 등)를 누르면 입력기를 `ABC`로 먼저 전환한 뒤 조합키를 앱에 전달합니다. 조합키가 연 팔레트나 검색창에서 바로 영문을 입력할 수 있습니다.
   - 조합키를 누르기 직전의 단어가 `Space` 때처럼 영문 오타로 판정되면(`ㅣㄴ` → `ls`) 함께 영문으로 바꿉니다. 진짜 한글(`안녕`)은 그대로 둡니다.
   - 영문 모드와 Cmd·Opt 조합은 그대로 두며, `Ctrl+Space`와 `Ctrl+Opt+Space`는 시스템의 입력기 전환 키로 계속 동작합니다. 메뉴에서 끌 수 있습니다.
```

- [ ] **Step 3: Run the tests**

Run: test command.
Expected: green.

- [ ] **Step 4: Commit**

```bash
git add Sources/KoEnFix.swift README.md
git commit -m "Add the Ctrl-combo switch to the menu and README."
```

---

### Task 7: Final verification and handover

**Files:**
- No source changes.

- [ ] **Step 1: Run the official test command**

```bash
./scripts/setup-koen-fix.sh --test
```

Expected: every line `✅ PASS`, ending with `🎉 All KoEnFix self-tests passed!`.

- [ ] **Step 2: Build with the package manifest**

```bash
swift build
```

Expected: `Build complete!`, no errors. Check whether `.build/` existed before this step (`ls -d .build`). If it did not, remove it afterwards with `rm -rf .build` so the tree is left as it was found. `.build/` is in `.gitignore`, so `git status --short` must not list it either way.

- [ ] **Step 3: Independent review**

Have a reviewer who did not write the code read the diff against the spec:

```bash
git diff 093df18 -- Sources/KoEnFix.swift README.md
```

Ask them to check, in this order:
1. Behavior with the toggle off equals the old behavior for every key (plain, Shift, Ctrl, Cmd, Opt, modifier).
2. A held combo always comes out: `beginReplacing()` clears the queue, so `replayAfter` must be enqueued after it, in both performers.
3. A replayed combo is tagged `SELF_EVENT_TAG`, so it cannot re-trigger.
4. `Ctrl+Space` and `Ctrl+Opt+Space` reach `passThrough`.
5. No force unwraps or array index risks in the new code.

Fix anything real they find, then re-run Step 1.

- [ ] **Step 4: Hand the manual checklist to the user**

These need a real keyboard and IME session, so only the user can run them. They start after `./scripts/setup-koen-fix.sh --install`. Do not run the install yourself: it replaces the running app, and the user decides when.

| # | 상황 | 기대 |
|---|---|---|
| a | Terminal, 한글 모드: `ㅣㄴ` + Ctrl+U | `ls`가 입력되고 줄이 지워지고 영문 모드 |
| b | VS Code, 한글 모드: Ctrl+P | 영문 모드에서 팔레트가 열리고 영문으로 입력됨 |
| c | VS Code, 한글 모드: Ctrl+Shift+P | 영문 모드에서 명령 팔레트가 열림 |
| d | tmux, 한글 모드: 접두어 Ctrl+B | 영문 모드로 바뀐 뒤 Ctrl+B가 tmux에 전달되어 접두어로 인식됨. 한글 모드에서는 Ctrl+ㅠ으로 가서 인식되지 않던 문제. 이어서 누르는 `d`도 영문으로 전달되어 detach |
| e | 한글 모드: Ctrl+Space | 시스템 토글만 동작. 한 번만 바뀜 |
| f | 영문 모드: Ctrl+P | 아무 변화 없음 |
| g | Terminal, 한글 모드: `abc`를 치고 Ctrl를 누른 채 Ctrl+A, Ctrl+E | 커서가 `abc` 뒤에 있음. 순서가 뒤바뀌면 앞에 놓임 |
| h | 한글 모드: `안녕` + Ctrl+S | `안녕` 유지, 영문 모드 |
| i | 한글 모드: `안녕하`(`하` 조합 중) + Ctrl+S | `안녕하` 유지, 영문 모드 |
| j | 한글 모드: Ctrl+2 | 영문 모드, 2번 데스크톱으로 이동 |
| k | VS Code, 한글 모드: Ctrl+P 직후 바로 Shift+글자 | Quick Open이 열림. 명령 팔레트(Ctrl+Shift+P)가 아니어야 함 |
| l | 한글 모드: `ㅣㄴ` + Space 직후 바로 Ctrl+Space | 변환은 `ls `로 끝나고, Ctrl+Space는 그 뒤에 한 번 전달되어 한글 모드로 바뀜 |
| m | TextEdit, 한글 모드: 글을 두 줄쯤 쓴 뒤 둘째 줄에서 Ctrl+Fn+← | 보기가 문서 처음으로 스크롤됨(Ctrl+Home). 커서가 한 단어만 왼쪽으로 가는(Ctrl+←) 일이 없어야 함. 기본 zsh은 두 키를 묶어 두지 않아 터미널에서는 확인할 수 없음 |

If a check fails, the user turns the menu toggle off (that restores the old behavior exactly) and reports the row. The follow-ups are below.

### Known limit left as is

A key typed in the 4–5 ms after a replacement ends, while the replayed trigger is still being posted, passes straight through and can reach the app before the trigger. Each further queued key widens the window. The window existed before this feature for deferred plain keys. Fix only if the user sees it: keep `isReplacingStorage` true during the replay, drain the queue again afterwards, and let `REPLAY_EVENT_TAG` events bypass `holdKeyWhileReplacing`.

### Pre-existing behavior that this feature does not change

- A plain or Shift+key held during a replacement is still replayed with no Fn, so an Fn+arrow pressed during a replacement loses its Fn. `DeferredUserKey.held` now records Fn on such a key, but the plain replay path posts `flags = []`. Fix if wanted: post `key.modifiers` there.
- The Shift+key replay takes its flags from the keyboard at replay time, so a modifier the user is holding then rides along. Optional fix: `keyStrokeFlags(from: shiftDown.flags, modifiers: key.modifiers)`.

---

## Follow-ups keyed to the manual checklist

Apply only when the user reports the matching failure.

### i fails: a composing syllable disappears on the switch-only path

The IME dropped the marked text on deactivation. Commit it by hand instead: unwind the marked strokes, switch, insert the syllable as text. First add a `recordsConversion` parameter to `performReplacement` so "하 → 하" does not land in 최근 변환 내역:

```swift
    private func performReplacement(
        deleteCount: Int,
        switchToKorean: Bool,
        insertText: String,
        fromLabel: String,
        toLabel: String,
        replayAfter: [DeferredUserKey] = [],
        recordsConversion: Bool = true
    ) {
        beginReplacing(replayAfter: replayAfter)
        if recordsConversion {
            recordConversion(from: fromLabel, to: toLabel)
        }
```

Then in `handleCtrlCombo`, capture the pending snapshot and take this path before the `switch`:

```swift
        let pending = buffer.isEmpty ? nil : buffer.snapshot()
        // ... ctrlComboAction(sim: pending, ...) ...
        let combo = DeferredUserKey(keyCode: keyCode, modifiers: modifiers)
        resetTracking()
        if case .switchInputSource = action, let pending, !pending.composingStrokes.isEmpty {
            // The IME drops a composing syllable when it is deactivated, so commit it by hand.
            performReplacement(
                deleteCount: pending.composingStrokes.count,
                switchToKorean: false,
                insertText: pending.composingText,
                fromLabel: pending.composingText,
                toLabel: pending.composingText,
                replayAfter: [combo],
                recordsConversion: false
            )
            return nil
        }
```

### j or g fails: system shortcuts do not fire, or combos typed while Ctrl is held go wrong

Drop the modifier press and release. Replace the `postSymbolicHotKey(...)` call inside the `if key.isCombo {` branch of `postReplayedUserKey` with a bare modified key pair. Its flags are explicit, so no modifier the user is holding can ride along:

```swift
        if key.isCombo {
            let src = CGEventSource(stateID: .hidSystemState)
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: key.keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: key.keyCode, keyDown: false) else {
                return
            }
            for event in [down, up] {
                event.flags = key.modifiers
                event.setIntegerValueField(.eventSourceUserData, value: SELF_EVENT_TAG)
                event.post(tap: .cghidEventTap)
                usleep(2_000)
            }
            return
        }
```
