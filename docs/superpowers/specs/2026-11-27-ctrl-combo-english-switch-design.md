# Ctrl 조합키 입력 시 한글 → 영문 전환

- 날짜: 2026-11-27
- 상태: 설계 승인됨 (2026-11-27, 대화에서)
- 대상 파일: `Sources/KoEnFix.swift`, `README.md`

## 배경

한글 모드에서 Ctrl 조합키를 누르면 지금은 단어 버퍼만 비우고 이벤트를 그대로 통과시킨다. 해당 코드는 `KoEnFixEngine.handleEvent`의 `hasCmd || hasCtrl || hasOpt` 분기이다. 그 결과 두 가지 문제가 생긴다.

- 조합키가 연 팔레트, 검색창, 프롬프트에서 한글 모드 그대로 글을 쓰게 된다. `main`을 쳐도 `ㅁㅁㅑㅜ`가 들어간다.
- 조합키를 누르기 직전에 친 영문 오타(`ㅣㄴ`)는 고쳐지지 않는다.

macOS는 수정자 키 눌림을 `flagsChanged`(type 12)로 보내고 KoEnFix의 탭은 `keyDown`(type 10)만 구독한다. 따라서 Ctrl를 누르기만 해서는 버퍼가 비워지지 않는다. 버퍼는 Ctrl 조합키의 `keyDown`이 도착한 순간 위 분기에서 비워진다. 이번 변경은 그 분기를 바꾸는 것이다.

## 목표

- 한글 모드에서 Ctrl 조합키가 들어오면 입력기를 `ABC`로 전환한 뒤 조합키를 앱에 전달한다.
- 조합키를 누른 순간 조합 중이던 단어가 `Space` 때와 같은 기준으로 영문 오타로 판정되면 영문으로 바꾼다.

## 비목표

- 어떤 조합에서도 영문 → 한글 전환은 하지 않는다.
- Cmd 단독 조합과 Opt 단독 조합은 바꾸지 않는다. 한글 문서 작업 중 Cmd+C, Cmd+V, Cmd+Z로 입력기가 잘못 바뀌는 일을 막기 위해서다.
- 조합별 허용·차단 목록은 만들지 않는다.
- `Ctrl+Space`와 `Ctrl+Opt+Space`(시스템 입력기 전환 단축키 60, 61)는 기존처럼 시스템이 처리한다. 단어도 바꾸지 않는다.
- `Space`로 이미 확정한 단어(`lastWordBeforeSpace`)와 Ctrl+클릭은 다루지 않는다.
- 소스 파일 분리는 하지 않는다. 설치 스크립트가 단일 파일을 컴파일한다.

## 사용자에게 보이는 동작

메뉴의 "Ctrl 조합키 입력 시 한글 → 영문 전환"(기본 켬)이 켜져 있고 한글 모드에서 Ctrl 조합키를 누르면 아래 표대로 동작한다.

| 조합 직전 상태 | 결과 | 예 |
|---|---|---|
| 영문 오타로 판정된 단어 | 단어를 영문으로 바꾸고 `ABC`로 전환 | `ㅣㄴ` + Ctrl+U → `ls`가 입력되고 영문 모드, 그다음 Ctrl+U가 앱에 전달 |
| 진짜 한글 단어 | 텍스트는 그대로 두고 `ABC`로 전환 | `안녕` + Ctrl+S → `안녕` 유지, 영문 모드, Ctrl+S 전달 |
| 아무것도 없음 | `ABC`로 전환 | Ctrl+P → 영문 모드, Ctrl+P 전달 |

- 판정 기준은 `Space`와 같다. `TypoDetector.shouldAutoConvertKoToEn(sim:mode:prefixSymbol:)`를 쓰고 `:`와 `-` 접두 문맥(`:ㅂ`, `-ㅣㅁ`)도 같이 반영한다.
- `보수적`과 `적극적` 모드는 같은 기준으로 단어를 바꾼다. `수동 변환 전용` 모드에서는 텍스트를 바꾸지 않고 입력기만 전환한다.
- 단어를 바꾼 경우 `Space` 때처럼 "최근 변환 내역"에 남긴다(`ㅣㄴ → ls`). 입력기만 전환한 경우에는 남기지 않는다.
- 조합키가 들어오면 `resetTracking()`으로 조합 중인 단어, 접두 기호, Space 직전 단어, En→Ko 실행 취소 대기를 지운다. 이는 다른 단축키의 기존 동작과 같다.

**Ctrl 조합키의 정의**: Control 플래그를 가진 `keyDown` 이벤트 중 수정자 키(키코드 54~63)가 아닌 것 전부. Shift, Opt, Cmd가 함께 눌린 조합(Ctrl+Shift+P, Ctrl+Opt+→)과 글자 키가 아닌 조합(Ctrl+방향키, Ctrl+Tab)도 포함한다.

## 선택한 방식: 조합키를 붙잡았다가 전환 뒤 전달

1. 탭이 Ctrl 조합키를 삼킨다.
2. 필요하면 단어를 교체한다(기존 `performReplacement`). 교체가 없으면 입력기만 전환한다(기존 `performInputSourceToggle`).
3. 전환이 끝난 뒤 같은 조합키를 합성 이벤트로 앱에 전달한다.

검토한 다른 방식은 "조합키는 즉시 통과시키고 전환은 뒤에서 병행"이다. 지연이 없다는 장점이 있지만, 앱이 조합키를 받는 시점과 입력기가 전환되는 시점의 순서가 보장되지 않는다. 팔레트나 검색창이 열리는 중에 전환이 들어가면 093df18에서 다뤘던 "포커스 앱의 입력 컨텍스트 전환"과 같은 종류의 경쟁이 생길 수 있어 선택하지 않았다.

**비용**: 한글 모드에서 Ctrl 조합키가 약 40~100ms 늦게 앱에 전달된다. 영문 모드에서는 지연이 없다.

**알려진 부작용**

- 한글로 글을 쓰다가 Ctrl 조합(코드 편집기의 Ctrl+/ 등)을 누르면 영문 모드로 바뀐다. 원치 않으면 메뉴에서 끈다.
- 데스크톱 전환(Ctrl+1~5)처럼 글 입력과 무관한 조합도 전환을 일으킨다.

## 구성 요소

### 1. 판정 함수 (`TypoDetector`)

```swift
enum CtrlComboAction: Equatable {
    case passThrough                    // 시스템 입력기 전환 단축키. 기존 동작 유지
    case switchInputSource              // 텍스트는 그대로, 입력기만 ABC
    case convertWord(SimulationResult)  // 단어를 영문으로 바꾸고 ABC
}

static func ctrlComboAction(
    isInputSourceSwitchHotKey: Bool,
    sim: SimulationResult?,   // 조합 직전 단어 버퍼. 비어 있으면 nil
    mode: AutoConvertMode,
    prefixSymbol: Character?
) -> CtrlComboAction
```

엔진이 먼저 저렴한 조건을 확인한다: 기능 켜짐, Control 플래그, 수정자 키 아님, 한글 모드. 이 함수는 남은 판정만 한다. 셀프 테스트가 이 함수로 판정표 전체를 고정한다.

### 2. 시스템 단축키 매칭 (`InputSourceManager`)

- `inputSourceSwitchHotKeys()`: `com.apple.symbolichotkeys`에서 60("이전 입력 소스 선택")과 61("입력 메뉴에서 다음 소스 선택") 중 켜진 항목을 `SymbolicHotKey`로 반환한다. 기존 `parseSymbolicHotKey(from:id:)`를 재사용한다.
- `shortcutModifiers(of:)`: 이벤트 플래그에서 Shift, Ctrl, Opt, Cmd만 남긴다.
- `matchesInputSourceSwitchHotKey(keyCode:modifiers:hotKeys:)`: 순수 함수. 키코드와 수정자 네 종이 모두 같아야 일치한다.
- 엔진은 한글 모드의 Ctrl 조합키에서만 설정을 읽는다.

개발 중인 시스템에서는 60이 Ctrl+Space, 61이 Ctrl+Opt+Space다(2026-11-27 확인). Ctrl+Shift+Space처럼 수정자가 다른 조합은 일치하지 않으므로 전환 대상이다.

일치하는 조합은 기존 단축키 분기로 되돌아가 버퍼를 비우고 통과한다.

### 3. 지연 재생 대기열

- 대기열 항목을 `(keyCode, isShift)`에서 `DeferredUserKey { keyCode, modifiers }`로 바꾼다. `modifiers`는 Shift, Ctrl, Opt, Cmd만 담는다.
- 대기열 본체를 `DeferredKeyQueue` 순수 타입으로 분리하고 엔진이 락 안에서만 쓴다.
- 교체·전환 중(`isReplacing`)에 `keyDown`이 들어오면 `deferredKey(keyDown:flags:ctrlComboSwitchEnabled:)` 순수 함수가 정한다. `nil`이면 즉시 통과이다.

| 교체 중 들어온 키 | 기능 켬 | 기능 끔 |
|---|---|---|
| 일반 키, Shift+키 | 대기열에 넣음 | 대기열에 넣음 |
| Ctrl 조합 | 대기열에 넣음 | 즉시 통과 |
| Cmd 단독·Opt 단독 조합 | 즉시 통과 | 즉시 통과 |
| 수정자 키 | 즉시 통과 | 즉시 통과 |

Ctrl 조합을 대기열에 넣는 이유는 트리거보다 먼저 앱에 도착하는 것을 막기 위해서다. 교체 중이라도 뒤에 누른 조합이 먼저 실행되면 Ctrl+W 다음 Ctrl+S 같은 연속 조합의 순서가 뒤바뀐다. 기능이 꺼져 있으면 트리거가 없으므로 기존 동작을 그대로 둔다.

교체 중에 들어온 Ctrl 조합은 전환을 일으키지 않는다. 전환을 일으키는 것은 교체 중이 아닐 때 들어온 첫 조합 하나뿐이다.

- 상한은 기존 그대로 16개다. 트리거는 항상 첫 항목이라 밀려나지 않는다.
- `performReplacement`와 `performInputSourceToggle`에 `replayAfter:` 인자를 추가한다. `beginReplacing()`이 대기열을 비운 뒤에 트리거를 첫 항목으로 넣는다.
- `completeReplacingAndReplay()`가 대기열 순서대로 재생한다.

### 4. 재생 이벤트

- Ctrl, Cmd, Opt 중 하나라도 가진 항목: 원래 이벤트의 Shift, Ctrl, Opt, Cmd 플래그를 그대로 붙인 `keyDown`과 `keyUp` 한 쌍을 보내고 `SELF_EVENT_TAG`를 건다. 탭이 이 태그를 무조건 통과시키므로 전환이 실패해도 다시 트리거되지 않는다.
- 수정자 키 자체의 눌림과 떼림은 합성하지 않는다. 사용자가 Ctrl를 아직 누르고 있을 때 합성 Ctrl 떼림이 들어가면 앱이 아는 수정자 상태가 실제와 어긋날 수 있기 때문이다.
- 일반 키와 Shift+키는 기존 `postReplayedUserKey` 동작을 그대로 쓴다.

### 5. 설정과 메뉴

- `KoEnFixEngine.switchToEnglishOnCtrlCombo: Bool`. 기본값은 `true`이고 UserDefaults 키는 `switchToEnglishOnCtrlCombo`이다. 다른 토글과 같이 `didSet`에서 저장하고 `onStateChange`를 부른다.
- 메뉴에 "Ctrl 조합키 입력 시 한글 → 영문 전환" 체크항목을 "터미널(tmux)에서 Enter 시 명령어 교정" 바로 아래에 둔다.
- README "주요 기능"에 다섯 번째 항목으로 추가한다. 동작, Ctrl+Space 제외, 메뉴에서 끌 수 있다는 점을 적는다.

## 오류와 경계 상황

- **전환 실패** (재시도 후에도 한글 모드): 조합키는 그대로 전달된다. 여전히 한글 모드이므로 다음 Ctrl 조합이 전환을 다시 시도한다. 재생 이벤트는 자체 태그라 무한 반복이 없다.
- **키 반복**: 교체 중 들어온 반복 `keyDown`도 대기열에 들어가 순서대로 전달된다.
- **조합 중인 음절이 있을 때 입력기만 전환**: `안녕하`에서 `하`가 조합 중인 상태로 Ctrl+S를 누르면 그 글자는 확정되어 남아야 한다. 기본은 입력기가 비활성화될 때의 기본 확정 동작에 맡긴다. 구현 첫 단계에서 확인하고, 글자가 사라지면 `performReplacement`로 조합 중인 글자만 지웠다가 `ABC` 상태에서 유니코드로 다시 넣는 방식으로 바꾼다.
- **마우스 이벤트, 영문 모드, 기능 끔, 수동 모드**: 위 표와 비목표대로 동작한다. 그 외 경로는 바꾸지 않는다.

## 테스트

셀프 테스트(`--self-test`)에 추가한다. 대상은 모두 순수 함수이다.

1. **판정표** (`ctrlComboAction`): 영문 오타(`ㅣㄴ`, `스ㅕㅌ`, `:ㅂ`) → `convertWord`. 진짜 한글(`안녕`, `해`)과 빈 버퍼 → `switchInputSource`. 수동 모드 + `ㅣㄴ` → `switchInputSource`. 시스템 단축키 → `passThrough`.
2. **단축키 매칭** (`matchesInputSourceSwitchHotKey`): 60(Ctrl+Space)과 61(Ctrl+Opt+Space)은 일치. 꺼진 항목은 무시. 다른 키나 다른 수정자는 불일치.
3. **대기열** (`deferredKey`, `DeferredKeyQueue`): 위 표의 모든 칸. 들어온 순서대로 나온다. 16개 상한을 지킨다.

수동 확인은 IME와 포커스 동작이 섞여 있어 유닛 테스트로 불가능하다. 구현 첫 단계에서 재생 방식 검증을 겸해 아래 표를 수행한다.

| # | 상황 | 기대 |
|---|---|---|
| a | Terminal, 한글 모드: `ㅣㄴ` + Ctrl+U | `ls`가 입력되고 줄이 지워지고 영문 모드 |
| b | VS Code, 한글 모드: Ctrl+P | 영문 모드에서 팔레트가 열리고 영문으로 입력됨 |
| c | VS Code, 한글 모드: Ctrl+Shift+P | 영문 모드에서 명령 팔레트가 열림 |
| d | tmux, 한글 모드: Ctrl+B 뒤에 `d` | 영문 모드라 `d`가 그대로 전달되어 detach |
| e | 한글 모드: Ctrl+Space | 시스템 토글만 동작. 한 번만 바뀜 |
| f | 영문 모드: Ctrl+P | 아무 변화 없음 |
| g | Ctrl를 누른 채 Ctrl+W, Ctrl+W 연속 | 순서대로 두 번 전달 |
| h | 한글 모드: `안녕` + Ctrl+S | `안녕` 유지, 영문 모드 |
| i | 한글 모드: `안녕하`(`하` 조합 중) + Ctrl+S | `안녕하` 유지, 영문 모드 |
| j | 한글 모드: Ctrl+2 | 영문 모드, 2번 데스크톱으로 이동 |

j에서 시스템 단축키가 재생되지 않으면 그 경로만 `postSymbolicHotKey`처럼 수정자 눌림과 떼림을 함께 합성하는 방식으로 바꾼다.
