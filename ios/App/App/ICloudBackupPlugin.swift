import Capacitor
import Foundation

/// Keeps the compact JSON backup in iCloud's key-value store. KVS is the right
/// fit for this app's structured preferences and workout history: it survives
/// uninstall, follows the user's iCloud account, and remains available offline
/// from the system cache. The web layer owns validation and conflict handling.
@objc(ICloudBackupPlugin)
public class ICloudBackupPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ICloudBackupPlugin"
    public let jsName = "ICloudBackup"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "status", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "read", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "write", returnType: CAPPluginReturnPromise)
    ]

    private let store = NSUbiquitousKeyValueStore.default
    private let dataKey = "gym-lib-backup-data"
    private let updatedAtKey = "gym-lib-backup-updated-at"
    private let maximumBackupBytes = 900_000

    public override func load() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeChanged(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        store.synchronize()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func status(_ call: CAPPluginCall) {
        call.resolve([
            "available": FileManager.default.ubiquityIdentityToken != nil
        ])
    }

    @objc func read(_ call: CAPPluginCall) {
        store.synchronize()
        call.resolve(currentRecord())
    }

    @objc func write(_ call: CAPPluginCall) {
        guard let data = call.getString("data"),
              let updatedAt = call.getString("updatedAt") else {
            call.reject("The iCloud backup is missing data or a timestamp.")
            return
        }
        guard data.lengthOfBytes(using: .utf8) <= maximumBackupBytes else {
            call.reject("The Gym Lib backup is too large for iCloud sync.")
            return
        }

        store.set(data, forKey: dataKey)
        store.set(updatedAt, forKey: updatedAtKey)
        store.synchronize()
        call.resolve()
    }

    @objc private func storeChanged(_ notification: Notification) {
        notifyListeners("backupChanged", data: currentRecord())
    }

    private func currentRecord() -> [String: Any] {
        guard let data = store.string(forKey: dataKey),
              let updatedAt = store.string(forKey: updatedAtKey) else {
            return [:]
        }
        return ["data": data, "updatedAt": updatedAt]
    }
}
