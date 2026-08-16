import Foundation

@MainActor
final class UserDefaultsSettingsStore: SettingsStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func bool(forKey key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func strings(forKey key: String) -> [String]? {
        defaults.stringArray(forKey: key)
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func set(_ value: [String], forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func set(_ value: Data, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}
