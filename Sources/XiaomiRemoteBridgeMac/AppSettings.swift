import Combine
import Foundation

final class AppSettings: ObservableObject {
    private enum Keys {
        static let gainDB = "gainDB"
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
        static let customMappingEnabled = "customMappingEnabled"
        static let legacyExclusiveHID = "exclusiveHID"
        static let buttonBindings = "buttonBindings"
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

    @Published var buttonBindings: [RemoteButton: ButtonBinding] {
        didSet { saveBindings() }
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

        if let data = defaults.data(forKey: Keys.buttonBindings) {
            let decoded = Self.decodeBindings(data)
            buttonBindings = Self.defaultBindings.merging(
                decoded
            ) { _, saved in saved }
        } else {
            buttonBindings = Self.defaultBindings
        }
    }

    func binding(for button: RemoteButton) -> ButtonBinding {
        buttonBindings[button] ?? .preset(.disabled)
    }

    func setBinding(_ binding: ButtonBinding, for button: RemoteButton) {
        customMappingEnabled = true
        buttonBindings[button] = binding
    }

    func resetBindings() {
        buttonBindings = Self.defaultBindings
    }

    private func saveBindings() {
        let raw = Dictionary(uniqueKeysWithValues: buttonBindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Keys.buttonBindings)
        }
    }

    private static func decodeBindings(_ data: Data) -> [RemoteButton: ButtonBinding] {
        guard let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: values.compactMap { key, value in
            guard
                let button = RemoteButton(rawValue: key),
                let valueData = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed),
                let binding = try? JSONDecoder().decode(ButtonBinding.self, from: valueData)
            else { return nil }
            return (button, binding)
        })
    }

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
}
