import Foundation

enum RemoteButton: String, CaseIterable, Codable, Identifiable {
    case power
    case up
    case left
    case ok
    case right
    case down
    case back
    case volumeUp = "volume_up"
    case home
    case volumeDown = "volume_down"
    case menu
    case tv

    var id: String { rawValue }

    var hidUsage: UInt16 {
        switch self {
        case .power: return 0x66
        case .up: return 0x52
        case .left: return 0x50
        case .ok: return 0x28
        case .right: return 0x4F
        case .down: return 0x51
        case .back: return 0xF1
        case .volumeUp: return 0x80
        case .home: return 0x4A
        case .volumeDown: return 0x81
        case .menu: return 0x65
        case .tv: return 0x35
        }
    }

    var shortLabel: String {
        switch self {
        case .power: return "电源"
        case .up: return "上"
        case .left: return "左"
        case .ok: return "OK"
        case .right: return "右"
        case .down: return "下"
        case .back: return "返回"
        case .volumeUp: return "+"
        case .home: return "主页"
        case .volumeDown: return "−"
        case .menu: return "菜单"
        case .tv: return "TV"
        }
    }

    var displayName: String {
        switch self {
        case .power: return "电源键"
        case .up: return "上键"
        case .left: return "左键"
        case .ok: return "确定键"
        case .right: return "右键"
        case .down: return "下键"
        case .back: return "返回键"
        case .volumeUp: return "音量 +"
        case .home: return "主页键"
        case .volumeDown: return "音量 -"
        case .menu: return "菜单键"
        case .tv: return "TV 键"
        }
    }

    static let usageMap = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0.hidUsage, $0) }
    )

    var nativeEvent: RemoteNativeEvent? {
        switch self {
        case .ok: return .keyboard(keyCode: 36)
        case .tv: return .keyboard(keyCode: 50)
        case .home: return .keyboard(keyCode: 115)
        case .right: return .keyboard(keyCode: 124)
        case .left: return .keyboard(keyCode: 123)
        case .down: return .keyboard(keyCode: 125)
        case .up: return .keyboard(keyCode: 126)
        case .menu: return .keyboard(keyCode: 110)
        case .power: return .systemKey(type: 6)
        case .volumeUp: return .systemKey(type: 0)
        case .volumeDown: return .systemKey(type: 1)
        case .back: return nil
        }
    }
}

enum RemoteNativeEvent: Equatable {
    case keyboard(keyCode: UInt16)
    case systemKey(type: Int32)
}

enum RemoteEventEdge: Equatable {
    case down
    case up
}

enum MappingProfile: String, CaseIterable, Codable, Identifiable {
    case general
    case codex
    case claudeCode = "claude_code"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "通用"
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        }
    }
}

enum ButtonGesture: String, CaseIterable, Codable {
    case press
    case hold

    var displayName: String {
        switch self {
        case .press: return "单击"
        case .hold: return "长按"
        }
    }
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

enum ButtonAction: String, CaseIterable, Codable, Identifiable {
    case disabled
    case escape
    case returnKey
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case deleteBackward
    case showDesktop
    case contextMenu
    case appSwitcher
    case volumeUp
    case volumeDown
    case volumeMute
    case playPause

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .disabled: return "禁用"
        case .escape: return "Escape"
        case .returnKey: return "Return"
        case .arrowUp: return "方向上"
        case .arrowDown: return "方向下"
        case .arrowLeft: return "方向左"
        case .arrowRight: return "方向右"
        case .deleteBackward: return "Delete（退格）"
        case .showDesktop: return "显示桌面"
        case .contextMenu: return "Shift-F10"
        case .appSwitcher: return "Command-Tab"
        case .volumeUp: return "系统音量 +"
        case .volumeDown: return "系统音量 -"
        case .volumeMute: return "系统静音"
        case .playPause: return "播放 / 暂停"
        }
    }
}

struct KeyCombo: Codable, Hashable {
    let keyCode: UInt16
    let keyLabel: String
    let control: Bool
    let option: Bool
    let shift: Bool
    let command: Bool

    var displayName: String {
        (control ? "⌃" : "") +
            (option ? "⌥" : "") +
            (shift ? "⇧" : "") +
            (command ? "⌘" : "") +
            keyLabel
    }
}

enum ShortcutKeyLabel {
    static func name(keyCode: UInt16, characters: String?) -> String {
        switch keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 109: return "F10"
        case 111: return "F12"
        case 115: return "Home"
        case 116: return "Page Up"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "Page Down"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            guard let characters, !characters.isEmpty else { return "键码 \(keyCode)" }
            return characters.uppercased()
        }
    }
}

enum ButtonBinding: Hashable, Codable {
    case preset(ButtonAction)
    case shortcut(KeyCombo)

    private enum CodingKeys: String, CodingKey {
        case shortcut
    }

    var displayName: String {
        switch self {
        case .preset(let action): action.displayName
        case .shortcut(let combo): "快捷键：\(combo.displayName)"
        }
    }

    var logDescription: String {
        switch self {
        case .preset(let action): action.rawValue
        case .shortcut(let combo): "shortcut:\(combo.displayName)"
        }
    }

    var isDisabled: Bool {
        self == .preset(.disabled)
    }

    func isRepeatable(on button: RemoteButton) -> Bool {
        guard case .preset(let action) = self, action != .disabled else { return false }
        switch button {
        case .up, .down, .left, .right, .back, .volumeUp, .volumeDown:
            return true
        default:
            return false
        }
    }

    init(from decoder: Decoder) throws {
        if let action = try? decoder.singleValueContainer().decode(ButtonAction.self) {
            self = .preset(action)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .shortcut(try container.decode(KeyCombo.self, forKey: .shortcut))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .preset(let action):
            var container = encoder.singleValueContainer()
            try container.encode(action)
        case .shortcut(let combo):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(combo, forKey: .shortcut)
        }
    }
}

struct ButtonMapping: Codable, Hashable {
    var press: ButtonBinding
    var hold: ButtonBinding

    func binding(for gesture: ButtonGesture) -> ButtonBinding {
        switch gesture {
        case .press: return press
        case .hold: return hold
        }
    }

    mutating func setBinding(_ binding: ButtonBinding, for gesture: ButtonGesture) {
        switch gesture {
        case .press: press = binding
        case .hold: hold = binding
        }
    }
}

enum RemoteHIDReportParser {
    static func usages(reportID: UInt32, data: Data) -> Set<UInt16>? {
        guard reportID == 1 else { return nil }
        var bytes = Array(data)
        if bytes.count == 7, bytes.first == UInt8(reportID) {
            bytes.removeFirst()
        }
        guard !bytes.isEmpty, bytes.count.isMultiple(of: 2) else { return nil }

        var result = Set<UInt16>()
        for index in stride(from: 0, to: bytes.count, by: 2) {
            let usage = UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
            if usage != 0 { result.insert(usage) }
        }
        return result
    }
}

enum HIDPermissionGate {
    static func canMonitor(
        mappingEnabled: Bool,
        inputMonitoringGranted: Bool,
        accessibilityGranted: Bool
    ) -> Bool {
        mappingEnabled && inputMonitoringGranted && accessibilityGranted
    }

    static func nextPermissionRequest(
        mappingEnabled: Bool,
        inputMonitoringGranted: Bool,
        accessibilityGranted: Bool
    ) -> HIDPermissionRequest {
        guard mappingEnabled else { return .none }
        if !inputMonitoringGranted { return .inputMonitoring }
        if !accessibilityGranted { return .accessibility }
        return .none
    }
}

enum HIDPermissionRequest: Equatable {
    case none
    case inputMonitoring
    case accessibility
}
