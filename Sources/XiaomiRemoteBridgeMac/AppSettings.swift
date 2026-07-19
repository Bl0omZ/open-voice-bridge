import Combine
import Foundation

struct ClaudeHostApplication: Identifiable, Hashable {
    let name: String
    let bundleIdentifier: String

    var id: String { bundleIdentifier }
}

final class AppSettings: ObservableObject {
    private enum Keys {
        static let gainDB = "gainDB"
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
        static let customMappingEnabled = "customMappingEnabled"
        static let legacyExclusiveHID = "exclusiveHID"
        static let legacyButtonBindings = "buttonBindings"
        static let profileBindings = "profileBindings"
        static let claudeHostBundleIDs = "claudeHostBundleIDs"
        static let peripheralIdentifier = "peripheralIdentifier"
    }

    private let defaults: UserDefaults

    @Published var gainDB: Double {
        didSet { defaults.set(gainDB, forKey: Keys.gainDB) }
    }

    @Published var selectedAudioDeviceUID: String {
        didSet { defaults.set(selectedAudioDeviceUID, forKey: Keys.selectedAudioDeviceUID) }
    }

    @Published var customMappingEnabled: Bool {
        didSet { defaults.set(customMappingEnabled, forKey: Keys.customMappingEnabled) }
    }

    @Published var profileBindings: [MappingProfile: [RemoteButton: ButtonMapping]] {
        didSet { saveProfileBindings() }
    }

    @Published var claudeHostBundleIDs: Set<String> {
        didSet {
            defaults.set(Array(claudeHostBundleIDs).sorted(), forKey: Keys.claudeHostBundleIDs)
        }
    }

    var peripheralIdentifier: UUID? {
        get {
            guard let raw = defaults.string(forKey: Keys.peripheralIdentifier) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            defaults.set(newValue?.uuidString, forKey: Keys.peripheralIdentifier)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        gainDB = defaults.object(forKey: Keys.gainDB) == nil
            ? 10.0
            : defaults.double(forKey: Keys.gainDB)
        selectedAudioDeviceUID = defaults.string(forKey: Keys.selectedAudioDeviceUID) ?? ""
        if defaults.object(forKey: Keys.customMappingEnabled) != nil {
            customMappingEnabled = defaults.bool(forKey: Keys.customMappingEnabled)
        } else {
            customMappingEnabled = defaults.bool(forKey: Keys.legacyExclusiveHID)
        }
        claudeHostBundleIDs = defaults.stringArray(forKey: Keys.claudeHostBundleIDs)
            .map(Set.init) ?? Self.defaultClaudeHostBundleIDs

        if let data = defaults.data(forKey: Keys.profileBindings) {
            profileBindings = Self.decodeProfileBindings(data)
        } else {
            var profiles = Self.defaultProfileBindings
            if let data = defaults.data(forKey: Keys.legacyButtonBindings) {
                var general = profiles[.general] ?? [:]
                for (button, binding) in Self.decodeBindings(data) {
                    var mapping = general[button] ?? Self.disabledMapping
                    mapping.press = binding
                    general[button] = mapping
                }
                profiles[.general] = general
            }
            profileBindings = profiles
        }
    }

    func profile(forBundleIdentifier bundleIdentifier: String?) -> MappingProfile {
        MappingProfileSelector.select(
            bundleIdentifier: bundleIdentifier,
            claudeHostBundleIDs: claudeHostBundleIDs
        )
    }

    func mapping(for button: RemoteButton, profile: MappingProfile) -> ButtonMapping {
        profileBindings[profile]?[button] ??
            Self.defaultProfileBindings[profile]?[button] ??
            Self.disabledMapping
    }

    func setBinding(
        _ binding: ButtonBinding,
        for button: RemoteButton,
        gesture: ButtonGesture,
        profile: MappingProfile
    ) {
        customMappingEnabled = true
        var mappings = profileBindings[profile] ?? Self.defaultProfileBindings[profile] ?? [:]
        var mapping = mappings[button] ?? Self.disabledMapping
        mapping.setBinding(binding, for: gesture)
        mappings[button] = mapping
        profileBindings[profile] = mappings
    }

    func resetBindings(for profile: MappingProfile) {
        profileBindings[profile] = Self.defaultProfileBindings[profile]
    }

    // Compatibility for the existing settings and HID callers until they become profile-aware.
    func binding(for button: RemoteButton) -> ButtonBinding {
        mapping(for: button, profile: .general).press
    }

    func setBinding(_ binding: ButtonBinding, for button: RemoteButton) {
        setBinding(binding, for: button, gesture: .press, profile: .general)
    }

    func resetBindings() {
        resetBindings(for: .general)
    }

    private func saveProfileBindings() {
        let raw = Dictionary(uniqueKeysWithValues: profileBindings.map { profile, mappings in
            (
                profile.rawValue,
                Dictionary(uniqueKeysWithValues: mappings.map { ($0.key.rawValue, $0.value) })
            )
        })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Keys.profileBindings)
        }
    }

    private static func decodeProfileBindings(
        _ data: Data
    ) -> [MappingProfile: [RemoteButton: ButtonMapping]] {
        guard let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return defaultProfileBindings
        }

        var result = defaultProfileBindings
        for (profileKey, value) in values {
            guard
                let profile = MappingProfile(rawValue: profileKey),
                let savedMappings = value as? [String: Any]
            else { continue }

            var mappings = result[profile] ?? [:]
            for (buttonKey, savedMapping) in savedMappings {
                guard
                    let button = RemoteButton(rawValue: buttonKey),
                    let valueData = try? JSONSerialization.data(
                        withJSONObject: savedMapping,
                        options: .fragmentsAllowed
                    ),
                    let mapping = try? JSONDecoder().decode(ButtonMapping.self, from: valueData)
                else { continue }
                mappings[button] = mapping
            }
            result[profile] = mappings
        }
        return result
    }

    private static func decodeBindings(_ data: Data) -> [RemoteButton: ButtonBinding] {
        guard let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: values.compactMap { key, value in
            guard
                let button = RemoteButton(rawValue: key),
                let valueData = try? JSONSerialization.data(
                    withJSONObject: value,
                    options: .fragmentsAllowed
                ),
                let binding = try? JSONDecoder().decode(ButtonBinding.self, from: valueData)
            else { return nil }
            return (button, binding)
        })
    }

    static let claudeHostCandidates = [
        ClaudeHostApplication(name: "Terminal", bundleIdentifier: "com.apple.Terminal"),
        ClaudeHostApplication(name: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty"),
        ClaudeHostApplication(name: "Warp", bundleIdentifier: "dev.warp.Warp-Stable"),
        ClaudeHostApplication(name: "iTerm", bundleIdentifier: "com.googlecode.iterm2"),
        ClaudeHostApplication(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode"),
        ClaudeHostApplication(name: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92"),
    ]

    static let defaultClaudeHostBundleIDs: Set<String> = [
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
    ]

    static let defaultBindings: [RemoteButton: ButtonBinding] = [
        .power: .preset(.escape),
        .up: .preset(.arrowUp),
        .left: .preset(.arrowLeft),
        .ok: .preset(.returnKey),
        .right: .preset(.arrowRight),
        .down: .preset(.arrowDown),
        .back: .preset(.deleteBackward),
        .volumeUp: .preset(.volumeUp),
        .home: .preset(.showDesktop),
        .volumeDown: .preset(.volumeDown),
        .menu: .preset(.contextMenu),
        .tv: .preset(.appSwitcher),
    ]

    static let defaultProfileBindings: [MappingProfile: [RemoteButton: ButtonMapping]] = {
        var general = baseMappings()
        general[.back]?.hold = shortcut(keyCode: 51, keyLabel: "Delete", command: true)

        var codex = baseMappings()
        codex[.back]?.hold = shortcut(keyCode: 51, keyLabel: "Delete", command: true)
        codex[.volumeUp] = ButtonMapping(
            press: shortcut(keyCode: 33, keyLabel: "[", shift: true, command: true),
            hold: shortcut(keyCode: 33, keyLabel: "[", command: true)
        )
        codex[.volumeDown] = ButtonMapping(
            press: shortcut(keyCode: 30, keyLabel: "]", shift: true, command: true),
            hold: shortcut(keyCode: 30, keyLabel: "]", command: true)
        )
        codex[.home] = ButtonMapping(
            press: shortcut(keyCode: 45, keyLabel: "N", command: true),
            hold: shortcut(keyCode: 35, keyLabel: "P", shift: true, command: true)
        )
        codex[.menu] = ButtonMapping(
            press: shortcut(keyCode: 5, keyLabel: "G", control: true, shift: true),
            hold: shortcut(keyCode: 11, keyLabel: "B", option: true, command: true)
        )
        codex[.tv] = ButtonMapping(
            press: shortcut(keyCode: 5, keyLabel: "G", command: true),
            hold: shortcut(keyCode: 48, keyLabel: "Tab", control: true)
        )

        var claudeCode = baseMappings()
        claudeCode[.ok]?.hold = shortcut(keyCode: 38, keyLabel: "J", control: true)
        claudeCode[.back]?.hold = shortcut(keyCode: 32, keyLabel: "U", control: true)
        claudeCode[.volumeUp] = ButtonMapping(
            press: shortcut(keyCode: 15, keyLabel: "R", control: true),
            hold: shortcut(keyCode: 11, keyLabel: "B", control: true)
        )
        claudeCode[.volumeDown] = ButtonMapping(
            press: shortcut(keyCode: 17, keyLabel: "T", control: true),
            hold: shortcut(keyCode: 1, keyLabel: "S", control: true)
        )
        claudeCode[.home] = ButtonMapping(
            press: shortcut(keyCode: 8, keyLabel: "C", control: true),
            hold: shortcut(keyCode: 31, keyLabel: "O", option: true)
        )
        claudeCode[.menu] = ButtonMapping(
            press: shortcut(keyCode: 48, keyLabel: "Tab", shift: true),
            hold: shortcut(keyCode: 17, keyLabel: "T", option: true)
        )
        claudeCode[.tv] = ButtonMapping(
            press: shortcut(keyCode: 31, keyLabel: "O", control: true),
            hold: shortcut(keyCode: 35, keyLabel: "P", option: true)
        )

        return [
            .general: general,
            .codex: codex,
            .claudeCode: claudeCode,
        ]
    }()

    private static let disabledMapping = ButtonMapping(
        press: .preset(.disabled),
        hold: .preset(.disabled)
    )

    private static func baseMappings() -> [RemoteButton: ButtonMapping] {
        Dictionary(uniqueKeysWithValues: defaultBindings.map {
            ($0.key, ButtonMapping(press: $0.value, hold: .preset(.disabled)))
        })
    }

    private static func shortcut(
        keyCode: UInt16,
        keyLabel: String,
        control: Bool = false,
        option: Bool = false,
        shift: Bool = false,
        command: Bool = false
    ) -> ButtonBinding {
        .shortcut(KeyCombo(
            keyCode: keyCode,
            keyLabel: keyLabel,
            control: control,
            option: option,
            shift: shift,
            command: command
        ))
    }
}
