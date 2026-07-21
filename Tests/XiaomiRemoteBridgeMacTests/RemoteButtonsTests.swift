import CoreGraphics
import Foundation
import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("Remote buttons")
struct RemoteButtonsTests {
    @Test func decodesLegacyPresetBinding() throws {
        let data = Data(#""escape""#.utf8)

        let binding = try JSONDecoder().decode(ButtonBinding.self, from: data)

        #expect(binding == .preset(.escape))
    }

    @Test func shortcutBindingRoundTrips() throws {
        let binding = ButtonBinding.shortcut(KeyCombo(
            keyCode: 48,
            keyLabel: "Tab",
            control: true,
            option: false,
            shift: false,
            command: false
        ))

        let encoded = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(ButtonBinding.self, from: encoded)

        #expect(decoded == binding)
    }

    @Test func shortcutDisplayUsesMacModifierSymbols() {
        let combo = KeyCombo(
            keyCode: 0,
            keyLabel: "A",
            control: true,
            option: true,
            shift: true,
            command: true
        )

        #expect(combo.displayName == "⌃⌥⇧⌘A")
        #expect(ButtonBinding.shortcut(combo).displayName == "快捷键：⌃⌥⇧⌘A")
    }

    @Test func savesAndReloadsShortcutBinding() throws {
        let suiteName = "XiaomiRemoteBridgeMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcut = ButtonBinding.shortcut(KeyCombo(
            keyCode: 48,
            keyLabel: "Tab",
            control: true,
            option: false,
            shift: false,
            command: false
        ))

        AppSettings(defaults: defaults).setBinding(shortcut, for: .menu)
        let reloaded = AppSettings(defaults: defaults)

        #expect(reloaded.binding(for: .menu) == shortcut)
    }

    @Test func changingBindingEnablesCustomMapping() throws {
        let suiteName = "XiaomiRemoteBridgeMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        settings.setBinding(.preset(.appSwitcher), for: .tv)

        #expect(settings.customMappingEnabled)
    }

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
        #expect(MappingProfileSelector.select(
            bundleIdentifier: nil,
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

    @Test func profileBindingsAndClaudeHostsPersistIndependently() throws {
        let suiteName = "XiaomiRemoteBridgeMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        settings.setBinding(
            .preset(.playPause),
            for: .menu,
            gesture: .hold,
            profile: .codex
        )
        settings.claudeHostBundleIDs = ["com.googlecode.iterm2"]
        let reloaded = AppSettings(defaults: defaults)

        #expect(reloaded.mapping(for: .menu, profile: .codex).hold == .preset(.playPause))
        #expect(reloaded.mapping(for: .menu, profile: .general).hold == .preset(.disabled))
        #expect(reloaded.claudeHostBundleIDs == ["com.googlecode.iterm2"])
    }

    @Test func malformedProfileBindingDoesNotDiscardValidSiblings() throws {
        let suiteName = "XiaomiRemoteBridgeMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let data = Data(#"""
        {
            "codex": {
                "tv": {
                    "press": {
                        "shortcut": {
                            "keyCode": 48,
                            "keyLabel": "Tab",
                            "control": true,
                            "option": false,
                            "shift": false,
                            "command": false
                        }
                    },
                    "hold": "disabled"
                },
                "back": {
                    "press": {"shortcut": {"keyCode": "invalid"}},
                    "hold": "disabled"
                }
            }
        }
        """#.utf8)
        defaults.set(data, forKey: "profileBindings")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.mapping(for: .tv, profile: .codex).press.displayName == "快捷键：⌃Tab")
        #expect(settings.mapping(for: .back, profile: .codex).press == .preset(.deleteBackward))
        #expect(settings.mapping(for: .tv, profile: .general).press == .preset(.appSwitcher))
    }

    @Test func defaultProfilesCoverApprovedHostsAndActions() throws {
        let suiteName = "XiaomiRemoteBridgeMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.claudeHostBundleIDs == [
            "com.mitchellh.ghostty",
            "dev.warp.Warp-Stable",
        ])
        #expect(settings.profile(forBundleIdentifier: "com.openai.codex") == .codex)
        #expect(settings.mapping(for: .back, profile: .general).hold.displayName == "快捷键：⌘Delete")
        #expect(settings.mapping(for: .ok, profile: .claudeCode).hold.displayName == "快捷键：⌃J")
    }

    @Test func malformedBindingDoesNotDiscardValidBindings() throws {
        let suiteName = "XiaomiRemoteBridgeMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let data = Data(#"""
        {
            "menu": {
                "shortcut": {
                    "keyCode": 48,
                    "keyLabel": "Tab",
                    "control": true,
                    "option": false,
                    "shift": false,
                    "command": false
                }
            },
            "back": {"shortcut": {"keyCode": "invalid"}}
        }
        """#.utf8)
        defaults.set(data, forKey: "buttonBindings")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.binding(for: .menu).displayName == "快捷键：⌃Tab")
        #expect(settings.binding(for: .back) == .preset(.deleteBackward))
    }

    @Test func onlyPresetBindingsRepeat() {
        let shortcut = ButtonBinding.shortcut(KeyCombo(
            keyCode: 48,
            keyLabel: "Tab",
            control: true,
            option: false,
            shift: false,
            command: false
        ))

        #expect(!shortcut.isRepeatable(on: .up))
        #expect(ButtonBinding.preset(.arrowUp).isRepeatable(on: .up))
        #expect(!ButtonBinding.preset(.returnKey).isRepeatable(on: .ok))
    }

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
        #expect(press.release() == nil)
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
        #expect(press.fireHold() == nil)
        #expect(press.release() == nil)
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

    @Test func shortcutModifiersMapToCGEventFlags() {
        let combo = KeyCombo(
            keyCode: 0,
            keyLabel: "A",
            control: true,
            option: true,
            shift: true,
            command: true
        )

        let flags = KeyboardInjector.flags(for: combo)

        #expect(flags == [.maskControl, .maskAlternate, .maskShift, .maskCommand])
    }

    @Test func shortcutEventSequenceReleasesControl() {
        let combo = KeyCombo(
            keyCode: 48,
            keyLabel: "Tab",
            control: true,
            option: false,
            shift: false,
            command: false
        )

        #expect(KeyboardInjector.eventSteps(for: combo) == [
            KeyboardEventStep(keyCode: 59, keyDown: true, flags: [.maskControl]),
            KeyboardEventStep(keyCode: 48, keyDown: true, flags: [.maskControl]),
            KeyboardEventStep(keyCode: 48, keyDown: false, flags: [.maskControl]),
            KeyboardEventStep(keyCode: 59, keyDown: false, flags: []),
        ])
    }

    @Test func shortcutKeyLabelsNormalizeSpecialKeys() {
        #expect(ShortcutKeyLabel.name(keyCode: 48, characters: "\t") == "Tab")
        #expect(ShortcutKeyLabel.name(keyCode: 0, characters: "a") == "A")
    }

    @Test func parsesRC003ReportOneUsages() {
        let data = Data([0xF1, 0x00, 0x80, 0x00, 0x00, 0x00])
        #expect(RemoteHIDReportParser.usages(reportID: 1, data: data) == Set([UInt16(0xF1), UInt16(0x80)]))
    }

    @Test func acceptsFirmwareReportWithIncludedID() {
        let data = Data([0x01, 0x35, 0x00, 0x00, 0x00, 0x00, 0x00])
        #expect(RemoteHIDReportParser.usages(reportID: 1, data: data) == Set([UInt16(0x35)]))
    }

    @Test func rejectsOtherReportsAndMalformedPayloads() {
        #expect(RemoteHIDReportParser.usages(reportID: 2, data: Data([0, 0])) == nil)
        #expect(RemoteHIDReportParser.usages(reportID: 1, data: Data()) == nil)
        #expect(RemoteHIDReportParser.usages(reportID: 1, data: Data([1])) == nil)
    }

    @Test func everyKnownUsageHasDefaultBinding() {
        for button in Set(RemoteButton.usageMap.values) {
            #expect(AppSettings.defaultBindings[button] != nil, Comment(rawValue: button.rawValue))
        }
    }

    @Test func everyProfileHasEveryKnownButton() {
        for profile in MappingProfile.allCases {
            for button in RemoteButton.allCases {
                #expect(
                    AppSettings.defaultProfileBindings[profile]?[button] != nil,
                    Comment(rawValue: "\(profile.rawValue):\(button.rawValue)")
                )
            }
        }
    }

    @Test func usesVerifiedRC003UsageTable() {
        #expect(RemoteButton.usageMap == [
            0x28: .ok,
            0x35: .tv,
            0x4A: .home,
            0x4F: .right,
            0x50: .left,
            0x51: .down,
            0x52: .up,
            0x65: .menu,
            0x66: .power,
            0x80: .volumeUp,
            0x81: .volumeDown,
            0xF1: .back,
        ])
    }

    @Test func HIDPermissionGateFailsClosed() {
        #expect(!HIDPermissionGate.canMonitor(
            mappingEnabled: true,
            inputMonitoringGranted: false,
            accessibilityGranted: true
        ))
        #expect(!HIDPermissionGate.canMonitor(
            mappingEnabled: true,
            inputMonitoringGranted: true,
            accessibilityGranted: false
        ))
        #expect(HIDPermissionGate.canMonitor(
            mappingEnabled: true,
            inputMonitoringGranted: true,
            accessibilityGranted: true
        ))
    }

    @Test func HIDPermissionRequestsAreSequentialAndOptIn() {
        #expect(HIDPermissionGate.nextPermissionRequest(
            mappingEnabled: false,
            inputMonitoringGranted: false,
            accessibilityGranted: false
        ) == .none)
        #expect(HIDPermissionGate.nextPermissionRequest(
            mappingEnabled: true,
            inputMonitoringGranted: false,
            accessibilityGranted: false
        ) == .inputMonitoring)
        #expect(HIDPermissionGate.nextPermissionRequest(
            mappingEnabled: true,
            inputMonitoringGranted: true,
            accessibilityGranted: false
        ) == .accessibility)
        #expect(HIDPermissionGate.nextPermissionRequest(
            mappingEnabled: true,
            inputMonitoringGranted: true,
            accessibilityGranted: true
        ) == .none)
    }

    @Test func savedBindingsMergeWithDefaults() throws {
        let suiteName = "XiaomiRemoteBridgeMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let saved = try JSONEncoder().encode([RemoteButton.back.rawValue: ButtonAction.disabled])
        defaults.set(saved, forKey: "buttonBindings")
        let settings = AppSettings(defaults: defaults)

        #expect(settings.binding(for: .back) == .preset(.disabled))
        #expect(settings.binding(for: .up) == .preset(.arrowUp))
    }

    @Test func migratesLegacyExclusiveToggleToCustomMappingToggle() throws {
        let suiteName = "XiaomiRemoteBridgeMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "exclusiveHID")
        let settings = AppSettings(defaults: defaults)

        #expect(settings.customMappingEnabled)
    }

    @Test func nativeEventDescriptorsCoverPotentialDuplicateEvents() {
        #expect(RemoteButton.up.nativeEvent == .keyboard(keyCode: 126))
        #expect(RemoteButton.ok.nativeEvent == .keyboard(keyCode: 36))
        #expect(RemoteButton.volumeUp.nativeEvent == .systemKey(type: 0))
        #expect(RemoteButton.back.nativeEvent == nil)
    }

    @Test func suppressesNativeKeyRepeatsUntilRemoteRelease() throws {
        let suppressor = KeyboardEventSuppressor()
        let source = try #require(CGEventSource(stateID: .hidSystemState))
        func event(isDown: Bool) throws -> CGEvent {
            try #require(CGEvent(
                keyboardEventSource: source,
                virtualKey: 50,
                keyDown: isDown
            ))
        }

        suppressor.arm(button: .tv, edge: .down)
        #expect(suppressor.handle(type: .keyDown, event: try event(isDown: true)))
        #expect(suppressor.handle(type: .keyDown, event: try event(isDown: true)))
        suppressor.arm(button: .tv, edge: .up)
        #expect(suppressor.handle(type: .keyUp, event: try event(isDown: false)))
        #expect(!suppressor.handle(type: .keyDown, event: try event(isDown: true)))
    }
}
