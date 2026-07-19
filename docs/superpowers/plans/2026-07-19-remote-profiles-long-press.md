# RC003 Remote Profiles and Long Press Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automatic General, Codex, and Claude Code button profiles plus configurable one-second long-press actions, then install a separately named test App.

**Architecture:** `AppSettings` owns persisted per-profile mappings and Claude host selections. Pure types in `RemoteButtons.swift` resolve a bundle identifier to a profile and resolve press/hold/release events to one action. `HIDRemoteMonitor` supplies real timers and forwards resulting bindings to the existing `KeyboardInjector`.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSWorkspace`, IOKit HID, Swift Testing, shell build/sign scripts.

```text
physical key-down
      |
      v
frontmost bundle ID --> Codex / selected terminal host / General
      |                         |
      v                         v
snapshot ButtonMapping    keep until key-up
      |
      +-- hold disabled --> send press now --> optional repeat --> key-up
      |
      +-- hold enabled  --> wait 1 second
                              |-- key-up first --> send press once
                              `-- timer first  --> send hold once --> key-up does nothing
```

## Global Constraints

- Preserve `/Applications/小米遥控器桥接.app`.
- Install this build only as `/Applications/小米遥控器桥接-快捷键测试.app` with bundle ID `com.kingwell.XiaomiRemoteBridgeMac.ShortcutTest`.
- The long-press threshold is exactly one second.
- Resolve the profile on physical key-down and retain it until key-up.
- Approval, decline, task deletion, commit, and push receive no default mapping.
- Reuse `ButtonBinding.preset(.disabled)` for an absent long-press action.
- Add no dependencies.

---

### Task 1: Preserve the custom-shortcut foundation

**Files:**
- Modify: `README.md`
- Modify: `Sources/XiaomiRemoteBridgeMac/KeyboardInjector.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/RemoteButtons.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/AppSettings.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/HIDRemoteMonitor.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/SettingsView.swift`
- Modify: `Tests/SelfTest/main.swift`
- Modify: `Tests/XiaomiRemoteBridgeMacTests/RemoteButtonsTests.swift`

**Interfaces:**
- Produces: `ButtonBinding.shortcut(KeyCombo)` persistence and `KeyboardInjector.eventSteps(for:)` with explicit modifier down/up events.

- [x] **Step 1: Correct the current Codex documentation**

Replace the current `Control-Tab` description with:

```markdown
| TV | 自定义 `Command-G` | Codex App 搜索会话，使用方向键选择并按 OK 确认 |
| 菜单 | 自定义 `Control-Tab` | Codex App 直接切换到下一个最近会话；松开 Control 后完成切换 |
```

- [x] **Step 2: Run the existing regression tests**

Run: `./scripts/test.sh && xcrun swift test`

Expected: self-test reports `failed=0`; Swift Testing reports all tests passed, including `shortcutEventSequenceReleasesControl()`.

- [x] **Step 3: Commit the verified shortcut foundation**

```bash
git add README.md Sources/XiaomiRemoteBridgeMac/AppSettings.swift Sources/XiaomiRemoteBridgeMac/HIDRemoteMonitor.swift Sources/XiaomiRemoteBridgeMac/KeyboardInjector.swift Sources/XiaomiRemoteBridgeMac/RemoteButtons.swift Sources/XiaomiRemoteBridgeMac/SettingsView.swift Tests/SelfTest/main.swift Tests/XiaomiRemoteBridgeMacTests/RemoteButtonsTests.swift
git commit -m "feat: support custom remote shortcuts"
```

### Task 2: Add profiles, mappings, and migration

**Files:**
- Modify: `Sources/XiaomiRemoteBridgeMac/RemoteButtons.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/AppSettings.swift`
- Modify: `Tests/XiaomiRemoteBridgeMacTests/RemoteButtonsTests.swift`
- Modify: `Tests/SelfTest/main.swift`

**Interfaces:**
- Produces: `MappingProfile`, `ButtonGesture`, `ButtonMapping`, `MappingProfileSelector.select(bundleIdentifier:claudeHostBundleIDs:)`.
- Produces: `AppSettings.mapping(for:profile:)`, `setBinding(_:for:gesture:profile:)`, `resetBindings(for:)`, `profile(forBundleIdentifier:)`, and persisted `claudeHostBundleIDs`.
- Preserves until Tasks 3 and 4: existing `binding(for:)`, `setBinding(_:for:)`, and `resetBindings()` methods as wrappers around the General profile so the whole app target compiles after this task.

- [ ] **Step 1: Write failing profile and migration tests**

Add these tests:

```swift
@Test func selectsProfileFromFrontmostApplication() {
    let hosts = Set(["com.mitchellh.ghostty"])
    #expect(MappingProfileSelector.select(
        bundleIdentifier: "com.openai.codex",
        claudeHostBundleIDs: hosts
    ) == .codex)
    #expect(MappingProfileSelector.select(
        bundleIdentifier: "com.mitchellh.ghostty",
        claudeHostBundleIDs: hosts
    ) == .claudeCode)
    #expect(MappingProfileSelector.select(
        bundleIdentifier: "com.apple.finder",
        claudeHostBundleIDs: hosts
    ) == .general)
}

@Test func migratesLegacyBindingsOnlyToGeneralProfile() throws {
    let suiteName = "XiaomiRemoteBridgeMacTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(try JSONEncoder().encode([
        RemoteButton.tv.rawValue: ButtonAction.disabled,
    ]), forKey: "buttonBindings")

    let settings = AppSettings(defaults: defaults)
    #expect(settings.mapping(for: .tv, profile: .general).press == .preset(.disabled))
    #expect(settings.mapping(for: .tv, profile: .codex).press.displayName == "快捷键：⌘G")
    #expect(settings.mapping(for: .tv, profile: .claudeCode).press.displayName == "快捷键：⌃O")
}
```

Also cover independent profile persistence, default Ghostty/Warp hosts, and recovery when one saved profile entry is malformed.

- [ ] **Step 2: Run the focused suite and verify RED**

Run: `xcrun swift test --filter RemoteButtonsTests`

Expected: compilation fails because `MappingProfile`, `ButtonMapping`, and the new settings methods do not exist.

- [ ] **Step 3: Add the profile domain types**

Add these interfaces to `RemoteButtons.swift`:

```swift
enum MappingProfile: String, CaseIterable, Codable, Identifiable {
    case general
    case codex
    case claudeCode = "claude_code"

    var id: String { rawValue }
}

enum ButtonGesture: String, CaseIterable, Codable {
    case press
    case hold
}

struct ButtonMapping: Codable, Hashable {
    var press: ButtonBinding
    var hold: ButtonBinding
}

enum MappingProfileSelector {
    static let codexBundleIdentifier = "com.openai.codex"

    static func select(
        bundleIdentifier: String?,
        claudeHostBundleIDs: Set<String>
    ) -> MappingProfile {
        if bundleIdentifier == codexBundleIdentifier { return .codex }
        if let bundleIdentifier, claudeHostBundleIDs.contains(bundleIdentifier) {
            return .claudeCode
        }
        return .general
    }
}
```

Add `MappingProfile.displayName`, `ButtonBinding.isDisabled`, and make `ButtonMapping` expose its binding for a `ButtonGesture`.

- [ ] **Step 4: Replace global bindings with persisted profile bindings**

Use one new `profileBindings` defaults key. Decode each profile and button independently through `JSONSerialization`, merge valid entries over exact defaults, and migrate legacy `buttonBindings` into `.general` only when the new key is absent.

Persist this JSON shape so every profile and button can recover independently:

```json
{
  "general": {
    "back": {"press": "deleteBackward", "hold": {"shortcut": {"keyCode": 51, "keyLabel": "Delete", "control": false, "option": false, "shift": false, "command": true}}}
  },
  "codex": {},
  "claude_code": {}
}
```

Use one private `shortcut(keyCode:keyLabel:control:option:shift:command:)` helper when constructing defaults; do not repeat full `KeyCombo` initializers in the mapping table.

Add this profile lookup to keep `HIDRemoteMonitor` independent from storage details:

```swift
func profile(forBundleIdentifier bundleIdentifier: String?) -> MappingProfile {
    MappingProfileSelector.select(
        bundleIdentifier: bundleIdentifier,
        claudeHostBundleIDs: claudeHostBundleIDs
    )
}
```

Keep the legacy settings methods as General-profile wrappers until their callers move in Tasks 3 and 4:

```swift
func binding(for button: RemoteButton) -> ButtonBinding {
    mapping(for: button, profile: .general).press
}

func setBinding(_ binding: ButtonBinding, for button: RemoteButton) {
    setBinding(binding, for: button, gesture: .press, profile: .general)
}

func resetBindings() {
    resetBindings(for: .general)
}
```

Use these host identifiers:

```swift
static let claudeHostCandidates = [
    (name: "Terminal", bundleIdentifier: "com.apple.Terminal"),
    (name: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty"),
    (name: "Warp", bundleIdentifier: "dev.warp.Warp-Stable"),
    (name: "iTerm", bundleIdentifier: "com.googlecode.iterm2"),
    (name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode"),
    (name: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92"),
]

static let defaultClaudeHostBundleIDs: Set<String> = [
    "com.mitchellh.ghostty",
    "dev.warp.Warp-Stable",
]
```

Create all default shortcuts with existing `KeyCombo`; use the key codes `[` 33, `]` 30, B 11, C 8, G 5, J 38, N 45, O 31, P 35, R 15, S 1, T 17, U 32, and Tab 48.

- [ ] **Step 5: Run focused tests and add self-test coverage**

Run: `xcrun swift test --filter RemoteButtonsTests`

Expected: all Remote Buttons tests pass.

Add self-test assertions for profile selection, legacy migration, Codex `Command-G`, Claude `Control-O`, and the default Claude hosts.

Run: `./scripts/test.sh`

Expected: `RESULT passed=<count> failed=0`.

- [ ] **Step 6: Commit profile persistence**

```bash
git add Sources/XiaomiRemoteBridgeMac/RemoteButtons.swift Sources/XiaomiRemoteBridgeMac/AppSettings.swift Tests/XiaomiRemoteBridgeMacTests/RemoteButtonsTests.swift Tests/SelfTest/main.swift
git commit -m "feat: add app-specific remote profiles"
```

### Task 3: Add the long-press state machine and HID timers

**Files:**
- Modify: `Sources/XiaomiRemoteBridgeMac/RemoteButtons.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/HIDRemoteMonitor.swift`
- Modify: `Tests/XiaomiRemoteBridgeMacTests/RemoteButtonsTests.swift`

**Interfaces:**
- Consumes: `ButtonMapping`, `MappingProfileSelector`, and `AppSettings.mapping(for:profile:)` from Task 2.
- Produces: `RemoteButtonPress.initialAction`, `fireHold()`, `release()`, and `cancel()`.

- [ ] **Step 1: Write failing state-machine tests**

```swift
@Test func shortPressDefersUntilReleaseWhenHoldExists() {
    let hold = ButtonBinding.shortcut(KeyCombo(
        keyCode: 51,
        keyLabel: "Delete",
        control: false,
        option: false,
        shift: false,
        command: true
    ))
    var press = RemoteButtonPress(mapping: ButtonMapping(
        press: .preset(.deleteBackward),
        hold: hold
    ))
    #expect(press.initialAction == nil)
    #expect(press.release() == .preset(.deleteBackward))
    #expect(press.fireHold() == nil)
}

@Test func longPressEmitsOnlyHoldAction() {
    let hold = ButtonBinding.shortcut(KeyCombo(
        keyCode: 32,
        keyLabel: "U",
        control: true,
        option: false,
        shift: false,
        command: false
    ))
    var press = RemoteButtonPress(mapping: ButtonMapping(
        press: .preset(.deleteBackward),
        hold: hold
    ))
    #expect(press.fireHold() == hold)
    #expect(press.release() == nil)
    #expect(press.fireHold() == nil)
}

@Test func mappingWithoutHoldRunsImmediatelyAndCanRepeat() {
    let mapping = ButtonMapping(
        press: .preset(.arrowUp),
        hold: .preset(.disabled)
    )
    var press = RemoteButtonPress(mapping: mapping)
    #expect(press.initialAction == .preset(.arrowUp))
    #expect(press.release() == nil)
    #expect(mapping.isRepeatable(on: .up))
}

@Test func cancelledPressCannotEmitAnAction() {
    var press = RemoteButtonPress(mapping: ButtonMapping(
        press: .preset(.deleteBackward),
        hold: .shortcut(KeyCombo(
            keyCode: 32,
            keyLabel: "U",
            control: true,
            option: false,
            shift: false,
            command: false
        ))
    ))
    press.cancel()
    #expect(press.fireHold() == nil)
    #expect(press.release() == nil)
}
```

- [ ] **Step 2: Run the focused suite and verify RED**

Run: `xcrun swift test --filter RemoteButtonsTests`

Expected: compilation fails because `RemoteButtonPress` does not exist.

- [ ] **Step 3: Implement the pure press state machine**

```swift
struct RemoteButtonPress {
    let mapping: ButtonMapping
    private var holdFired = false
    private var released = false

    var initialAction: ButtonBinding? {
        mapping.hold.isDisabled ? mapping.press : nil
    }

    mutating func fireHold() -> ButtonBinding? {
        guard !released, !holdFired, !mapping.hold.isDisabled else { return nil }
        holdFired = true
        return mapping.hold
    }

    mutating func release() -> ButtonBinding? {
        guard !released else { return nil }
        released = true
        return holdFired || mapping.hold.isDisabled ? nil : mapping.press
    }

    mutating func cancel() {
        released = true
    }
}
```

`ButtonMapping.isRepeatable(on:)` returns true only when `hold.isDisabled` and `press.isRepeatable(on:)`.

- [ ] **Step 4: Integrate profile snapshots and one-second timers**

In `HIDRemoteMonitor`, add `activePresses` and `holdTimers` dictionaries keyed by HID usage. On key-down:

1. Read `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`.
2. Select the profile through `settings.profile(forBundleIdentifier:)`.
3. Snapshot that profile's `ButtonMapping` into `RemoteButtonPress`.
4. Send `initialAction` immediately or schedule one timer for `.now() + .seconds(1)`.
5. Start repeat only for mappings where `isRepeatable(on:)` is true.

On key-up, cancel both timers and send `release()`. Call `cancel()` on every active press before removing it in `stop()`, device removal, and permission revocation. Keep all mutation on the main queue so timer and HID callbacks cannot race.

- [ ] **Step 5: Run focused and full tests**

Run: `xcrun swift test --filter RemoteButtonsTests && ./scripts/test.sh`

Expected: all focused tests pass and self-test reports `failed=0`.

- [ ] **Step 6: Commit long-press handling**

```bash
git add Sources/XiaomiRemoteBridgeMac/RemoteButtons.swift Sources/XiaomiRemoteBridgeMac/HIDRemoteMonitor.swift Tests/XiaomiRemoteBridgeMacTests/RemoteButtonsTests.swift
git commit -m "feat: add remote long-press actions"
```

### Task 4: Add the profile-aware settings interface

**Files:**
- Modify: `Sources/XiaomiRemoteBridgeMac/SettingsView.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: profile settings methods and host candidates from Task 2.
- Produces: user-editable press/hold mappings for every profile and host checkboxes.

- [ ] **Step 1: Add profile and recording state**

Add `selectedProfile`, `recordingGesture`, and `frontmostBundleIdentifier` state. Initialize the identifier in `.onAppear` from `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`, then observe `NSWorkspace.didActivateApplicationNotification` and refresh it from the notification's running application.

- [ ] **Step 2: Add profile and host controls**

Add a segmented Picker for General, Codex, and Claude Code. Display the profile selected for the current frontmost bundle identifier. Under the Claude Code segment, display one Toggle for each `claudeHostCandidates` entry.

- [ ] **Step 3: Render press and hold editors**

For each button item, keep the button identity in the first line and stack two compact editor lines labeled “单击” and “长按” below it. Do not place two 175-point Pickers side by side in the existing 760-point window. Each editor uses the existing preset Picker and shortcut recorder. Store the recording target as profile + button + gesture so switching profiles, losing focus, or leaving the tab cancels recording without writing to the wrong mapping.

- [ ] **Step 4: Document the default profiles**

Replace the single mapping table in `README.md` with the exact default table from `docs/superpowers/specs/2026-07-19-remote-profiles-long-press-design.md`. Explain that selected terminal hosts use Claude Code mappings for every tab in that host.

- [ ] **Step 5: Compile and run all tests**

Run: `./scripts/test.sh && xcrun swift test`

Expected: self-test reports `failed=0`; all Swift tests pass; SwiftUI compiles.

Launch the settings window and verify that all three profile segments fit at 760 x 600, each row exposes separate single/hold controls, and host toggles do not overlap the mapping list.

- [ ] **Step 6: Commit the settings interface**

```bash
git add Sources/XiaomiRemoteBridgeMac/SettingsView.swift README.md
git commit -m "feat: configure remote profiles and hold actions"
```

### Task 5: Review, build, verify, and install the test App

**Files:**
- Verify: all modified source, tests, documentation, and scripts.
- Build: `dist/小米遥控器桥接.app`
- Install: `/Applications/小米遥控器桥接-快捷键测试.app`

**Interfaces:**
- Produces: a signed, launchable test App with a separate bundle identifier.

- [ ] **Step 1: Review the complete diff against the design**

Check profile selection, migration, timer cancellation, repeated HID reports, permission loss, shortcut modifier release, settings recorder cleanup, and the exclusion of high-risk defaults. Apply only fixes required by the design or correctness.

- [ ] **Step 2: Run final verification**

```bash
git diff --check
./scripts/test.sh
xcrun swift test
./scripts/build-app.sh
./scripts/verify-app.sh
```

Expected: every command exits 0; self-test reports no failures; Swift Testing reports all tests passed; App verification prints `APP VERIFY PASS`.

- [ ] **Step 3: Replace only the separately named test App**

```bash
osascript -e 'tell application id "com.kingwell.XiaomiRemoteBridgeMac.ShortcutTest" to quit' || true
rm -rf /Applications/小米遥控器桥接-快捷键测试.app
ditto dist/小米遥控器桥接.app /Applications/小米遥控器桥接-快捷键测试.app
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 小米遥控器桥接-快捷键测试' /Applications/小米遥控器桥接-快捷键测试.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Set :CFBundleName 小米遥控器桥接-快捷键测试' /Applications/小米遥控器桥接-快捷键测试.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.kingwell.XiaomiRemoteBridgeMac.ShortcutTest' /Applications/小米遥控器桥接-快捷键测试.app/Contents/Info.plist
codesign --force --deep --sign - /Applications/小米遥控器桥接-快捷键测试.app
codesign --verify --deep --strict /Applications/小米遥控器桥接-快捷键测试.app
open /Applications/小米遥控器桥接-快捷键测试.app
```

Expected: the test App launches without replacing `/Applications/小米遥控器桥接.app`.

- [ ] **Step 4: Verify the running test App**

Run:

```bash
pgrep -fl '/Applications/小米遥控器桥接-快捷键测试.app/Contents/MacOS/XiaomiRemoteBridgeMac'
plutil -extract CFBundleIdentifier raw -o - /Applications/小米遥控器桥接-快捷键测试.app/Contents/Info.plist
codesign --verify --deep --strict /Applications/小米遥控器桥接-快捷键测试.app
```

Expected: one running process, bundle ID `com.kingwell.XiaomiRemoteBridgeMac.ShortcutTest`, and valid ad-hoc signature.

## What Already Exists

- `ButtonBinding` and `KeyCombo` already encode preset and custom shortcuts; the plan extends their use to press and hold slots.
- `AppSettings.decodeBindings` already recovers valid entries when one legacy binding is corrupt; the profile decoder keeps this behavior.
- `HIDRemoteMonitor` already detects key-down/key-up edges and owns repeat timers; the plan adds hold timers in the same main-queue module.
- `KeyboardInjector.eventSteps(for:)` already sends and releases explicit modifier keys, including the repaired Control-Tab sequence.

## NOT in Scope

- Multi-key macros: none of the approved defaults require sequential shortcuts.
- Detecting Claude Code inside an individual terminal tab: macOS exposes the host application reliably, so users select which hosts use the Claude profile.
- Default approval, decline, deletion, commit, or push actions: these remain deliberate screen actions.
- BlackHole packaging and automatic audio selection: this follows after the user validates the input workflow.
- Replacing or publishing the production App: this run installs only the separately identified test App.

## Failure Modes Reviewed

| Failure | Prevention | Evidence |
|---|---|---|
| Application changes during a hold | Snapshot mapping on key-down | Profile selector and press-state tests |
| Hold timer fires after key-up | Cancel timer and make `release()` terminal | Short/long/cancel state tests |
| Permission disappears during a hold | Cancel active presses from the existing permission release path | Cancel state test plus manual permission path review |
| One saved mapping is corrupt | Decode and merge each profile/button independently | Malformed-entry migration test |
| Terminal host applies Claude keys to a normal shell | Explicit host checkboxes and README warning | Settings build plus manual App test |

## Test Coverage Diagram

```text
CODE PATHS                                           USER FLOWS
[+] MappingProfileSelector                           [+] Switch applications
  |-- [TEST] Codex bundle -> Codex                     |-- [TEST] Codex receives Codex defaults
  |-- [TEST] selected host -> Claude Code              |-- [TEST] selected terminal receives Claude defaults
  |-- [TEST] other/nil -> General                      `-- [TEST] other app receives General defaults
[+] AppSettings                                     [+] Configure mappings
  |-- [TEST] no saved data -> defaults                 |-- [BUILD+MANUAL] choose profile
  |-- [TEST] legacy data -> General only               |-- [BUILD+MANUAL] edit press and hold
  |-- [TEST] new data -> independent profiles          |-- [BUILD+MANUAL] record custom shortcut
  `-- [TEST] malformed entry -> one default            `-- [BUILD+MANUAL] toggle Claude hosts
[+] RemoteButtonPress                               [+] Use a physical button
  |-- [TEST] no hold -> immediate action + repeat      |-- [TEST] tap -> one press action
  |-- [TEST] release before timer -> press once         |-- [TEST] hold 1 second -> one hold action
  |-- [TEST] timer before release -> hold once          |-- [TEST] disconnect/revoke -> no late action
  |-- [TEST] repeated timer/release -> no duplicate     `-- [MANUAL HARDWARE] RC003 HID end-to-end
  `-- [TEST] cancel -> no later action
[+] KeyboardInjector
  `-- [TEST] modifier down/key/down/up/modifier up
```

Pure profile, migration, state, and keyboard-event branches receive automated tests. SwiftUI layout and real RC003 timing remain manual because the repository has no UI-test target or HID simulator; the built and running test App is the integration artifact the user will exercise.

## Execution Order

Sequential implementation, no parallelization opportunity. Tasks 2 through 4 share the same mapping types and settings interfaces; separate worktrees would create avoidable merge conflicts.

## Plan Engineering Review

- Step 0 Scope Challenge: accepted as-is. The new work modifies five existing implementation/test files after preserving the current shortcut foundation; it adds no dependency or separate runtime module.
- Architecture: two interface-boundary issues found and fixed. Task 2 now keeps General-profile compatibility wrappers and produces `profile(forBundleIdentifier:)`.
- Code quality: one layout issue found and fixed. Press and hold editors stack vertically inside the existing window width.
- Tests: one cancellation gap found and fixed. `RemoteButtonPress.cancel()` now has a required regression test.
- Performance: no issue. HID reports and timers stay on the existing main queue with at most one hold timer per pressed button.
- Failure modes: five reviewed, zero silent critical gaps.
- Outside voice: critic review ran; all three findings were incorporated, with no unresolved disagreement.
- Parallelization: sequential; shared mapping and settings files make parallel worktrees counterproductive.
- Lake score: 4/4 recommendations use the complete option.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | not run | Product direction already approved in the design interview |
| Codex Review | `/codex review` | Independent 2nd opinion | 1 | clear after fixes | 3 findings accepted and repaired in the plan |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | clear | 4 issues fixed, 0 critical gaps |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | not run | Native settings layout constrained explicitly in Task 4 |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | not run | No developer-facing interface added |

- **UNRESOLVED:** 0
- **VERDICT:** ENG CLEARED — ready to implement.
