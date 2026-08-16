import Foundation

@MainActor
protocol SettingsStoring: AnyObject {
    func bool(forKey key: String) -> Bool?
    func string(forKey key: String) -> String?
    func strings(forKey key: String) -> [String]?
    func data(forKey key: String) -> Data?
    func set(_ value: Bool, forKey key: String)
    func set(_ value: String, forKey key: String)
    func set(_ value: [String], forKey key: String)
    func set(_ value: Data, forKey key: String)
}
