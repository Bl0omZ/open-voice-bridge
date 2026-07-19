import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct KeyboardEventStep: Equatable {
    let keyCode: CGKeyCode
    let keyDown: Bool
    let flags: CGEventFlags
}

enum KeyboardInjector {
    static let syntheticEventMarker: Int64 = 0x5849_414F

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func flags(for combo: KeyCombo) -> CGEventFlags {
        var flags: CGEventFlags = []
        if combo.control { flags.insert(.maskControl) }
        if combo.option { flags.insert(.maskAlternate) }
        if combo.shift { flags.insert(.maskShift) }
        if combo.command { flags.insert(.maskCommand) }
        return flags
    }

    static func eventSteps(for combo: KeyCombo) -> [KeyboardEventStep] {
        var modifiers: [(keyCode: CGKeyCode, flag: CGEventFlags)] = []
        if combo.control { modifiers.append((59, .maskControl)) }
        if combo.option { modifiers.append((58, .maskAlternate)) }
        if combo.shift { modifiers.append((56, .maskShift)) }
        if combo.command { modifiers.append((55, .maskCommand)) }

        var activeFlags: CGEventFlags = []
        var steps: [KeyboardEventStep] = []
        for modifier in modifiers {
            activeFlags.insert(modifier.flag)
            steps.append(KeyboardEventStep(
                keyCode: modifier.keyCode,
                keyDown: true,
                flags: activeFlags
            ))
        }
        steps.append(KeyboardEventStep(keyCode: combo.keyCode, keyDown: true, flags: activeFlags))
        steps.append(KeyboardEventStep(keyCode: combo.keyCode, keyDown: false, flags: activeFlags))
        for modifier in modifiers.reversed() {
            activeFlags.remove(modifier.flag)
            steps.append(KeyboardEventStep(
                keyCode: modifier.keyCode,
                keyDown: false,
                flags: activeFlags
            ))
        }
        return steps
    }

    @discardableResult
    static func send(_ binding: ButtonBinding) -> Bool {
        switch binding {
        case .preset(let action):
            return send(action)
        case .shortcut(let combo):
            guard isAccessibilityTrusted else { return false }
            return postShortcut(combo)
        }
    }

    private static func send(_ action: ButtonAction) -> Bool {
        guard action != .disabled else { return true }
        guard isAccessibilityTrusted else { return false }

        switch action {
        case .disabled:
            return true
        case .escape:
            postKey(code: 53)
        case .returnKey:
            postKey(code: 36)
        case .arrowUp:
            postKey(code: 126)
        case .arrowDown:
            postKey(code: 125)
        case .arrowLeft:
            postKey(code: 123)
        case .arrowRight:
            postKey(code: 124)
        case .deleteBackward:
            postKey(code: 51)
        case .showDesktop:
            postKey(code: 103, flags: .maskSecondaryFn)
        case .contextMenu:
            postKey(code: 109, flags: .maskShift)
        case .appSwitcher:
            postKey(code: 48, flags: .maskCommand)
        case .volumeUp:
            postSystemKey(type: 0)
        case .volumeDown:
            postSystemKey(type: 1)
        case .volumeMute:
            postSystemKey(type: 7)
        case .playPause:
            postSystemKey(type: 16)
        }
        return true
    }

    private static func postKey(code: CGKeyCode, flags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postShortcut(_ combo: KeyCombo) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        var events: [CGEvent] = []
        for step in eventSteps(for: combo) {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: step.keyCode,
                keyDown: step.keyDown
            ) else { return false }
            event.flags = step.flags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            events.append(event)
        }
        events.forEach { $0.post(tap: .cghidEventTap) }
        return true
    }

    private static func postSystemKey(type: Int32) {
        postSystemKey(type: type, isDown: true)
        postSystemKey(type: type, isDown: false)
    }

    private static func postSystemKey(type: Int32, isDown: Bool) {
        let keyState = isDown ? 0xA : 0xB
        let data1 = Int((type << 16) | Int32(keyState << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        guard let cgEvent = event.cgEvent else { return }
        cgEvent.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        cgEvent.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
