import Capacitor
import Foundation
import Security

@objc(SecureStoragePlugin)
final class SecureStoragePlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "SecureStoragePlugin"
    let jsName = "SecureStorage"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "set", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "get", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "remove", returnType: CAPPluginReturnPromise)
    ]

    private let service = "net.vipertec.viperchat.secure-storage"

    private var sharedAccessGroup: String? {
        guard let prefix = Bundle.main.object(
            forInfoDictionaryKey: "AppIdentifierPrefix"
        ) as? String, !prefix.isEmpty else {
            return nil
        }
        return "\(prefix)net.vipertec.viperchat.shared"
    }

    @objc func set(_ call: CAPPluginCall) {
        guard let key = call.getString("key"), !key.isEmpty,
              let value = call.getString("value"),
              let data = value.data(using: .utf8) else {
            call.reject("key and value are required")
            return
        }

        let query = keychainQuery(for: key, shared: true)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)

        guard status == errSecSuccess else {
            call.reject("Unable to store the secure value", String(status))
            return
        }
        call.resolve()
    }

    @objc func get(_ call: CAPPluginCall) {
        guard let key = call.getString("key"), !key.isEmpty else {
            call.reject("key is required")
            return
        }

        let sharedResult = readValue(for: key, shared: true)
        var status = sharedResult.status
        var data = sharedResult.data
        if status == errSecItemNotFound {
            let legacyResult = readValue(for: key, shared: false)
            status = legacyResult.status
            data = legacyResult.data
            if status == errSecSuccess, let data {
                migrateLegacyValue(data, for: key)
            }
        }
        if status == errSecItemNotFound {
            call.resolve(["value": NSNull()])
            return
        }
        guard status == errSecSuccess,
              let data,
              let value = String(data: data, encoding: .utf8) else {
            call.reject("Unable to read the secure value", String(status))
            return
        }
        call.resolve(["value": value])
    }

    @objc func remove(_ call: CAPPluginCall) {
        guard let key = call.getString("key"), !key.isEmpty else {
            call.reject("key is required")
            return
        }

        let statuses = [
            SecItemDelete(keychainQuery(for: key, shared: true) as CFDictionary),
            SecItemDelete(keychainQuery(for: key, shared: false) as CFDictionary)
        ]
        guard statuses.allSatisfy({ $0 == errSecSuccess || $0 == errSecItemNotFound }) else {
            call.reject("Unable to remove the secure value", String(statuses.first { $0 != errSecSuccess && $0 != errSecItemNotFound }!))
            return
        }
        call.resolve()
    }

    private func keychainQuery(for key: String, shared: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if shared, let sharedAccessGroup {
            query[kSecAttrAccessGroup as String] = sharedAccessGroup
        }
        return query
    }

    private func readValue(for key: String, shared: Bool) -> (status: OSStatus, data: Data?) {
        var query = keychainQuery(for: key, shared: shared)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    private func migrateLegacyValue(_ data: Data, for key: String) {
        let sharedQuery = keychainQuery(for: key, shared: true)
        SecItemDelete(sharedQuery as CFDictionary)

        var attributes = sharedQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess {
            SecItemDelete(keychainQuery(for: key, shared: false) as CFDictionary)
        }
    }
}
