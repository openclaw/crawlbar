import Foundation
import Security

public enum CrawlSecretStoreError: LocalizedError, Sendable {
    case readFailed(OSStatus)
    case writeFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .readFailed(status):
            "Keychain read failed with status \(status)"
        case let .writeFailed(status):
            "Keychain write failed with status \(status)"
        case let .deleteFailed(status):
            "Keychain delete failed with status \(status)"
        }
    }
}

public struct CrawlSecretStore: @unchecked Sendable {
    private let service: String

    public init(service: String = "com.vincentkoc.CrawlBar") {
        self.service = service
    }

    public func value(appID: CrawlAppID, optionID: String) throws -> String? {
        var query = self.baseQuery(appID: appID, optionID: optionID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CrawlSecretStoreError.readFailed(status)
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String?, appID: CrawlAppID, optionID: String) throws {
        var query = self.baseQuery(appID: appID, optionID: optionID)
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess, deleteStatus != errSecItemNotFound {
            throw CrawlSecretStoreError.deleteFailed(deleteStatus)
        }

        guard let value = value?.nilIfBlank else { return }
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CrawlSecretStoreError.writeFailed(addStatus)
        }
    }

    private func baseQuery(appID: CrawlAppID, optionID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: "\(appID.rawValue).\(optionID)",
        ]
    }
}
