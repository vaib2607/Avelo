import Foundation
import Security

public protocol CompanyKeyStoring: Sendable {
    func generateKey() throws -> Data
    func store(key: Data, companyId: Company.ID) throws
    func retrieve(companyId: Company.ID) throws -> Data?
    func delete(companyId: Company.ID) throws
}

public struct CompanyKeyStore: CompanyKeyStoring {
    private let service: String

    public init(service: String = "com.avelo.desktop.company-key") {
        self.service = service
    }

    public func generateKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AppError.database(.openFailed("Unable to generate encryption key: OSStatus \(status)"))
        }
        return Data(bytes)
    }

    public func store(key: Data, companyId: Company.ID) throws {
        guard key.count == 32 else {
            throw AppError.database(.openFailed("Company encryption key must be 32 bytes."))
        }
        let query = baseQuery(companyId: companyId)
            .merging([
                kSecValueData as String: key,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]) { _, new in new }
        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                baseQuery(companyId: companyId) as CFDictionary,
                [kSecValueData as String: key] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw AppError.database(.openFailed("Unable to update company encryption key: OSStatus \(updateStatus)"))
            }
        default:
            throw AppError.database(.openFailed("Unable to store company encryption key: OSStatus \(status)"))
        }
    }

    public func retrieve(companyId: Company.ID) throws -> Data? {
        let query = baseQuery(companyId: companyId)
            .merging([
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]) { _, new in new }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw AppError.database(.openFailed("Company encryption key was not returned as data."))
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw AppError.database(.openFailed("Unable to retrieve company encryption key: OSStatus \(status)"))
        }
    }

    public func delete(companyId: Company.ID) throws {
        let status = SecItemDelete(baseQuery(companyId: companyId) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw AppError.database(.openFailed("Unable to delete company encryption key: OSStatus \(status)"))
        }
    }

    private func baseQuery(companyId: Company.ID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: companyId.uuidString
        ]
    }
}

public final class InMemoryCompanyKeyStore: CompanyKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [Company.ID: Data] = [:]

    public init() {}

    public func generateKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255)
        }
        return Data(bytes)
    }

    public func store(key: Data, companyId: Company.ID) throws {
        guard key.count == 32 else {
            throw AppError.database(.openFailed("Company encryption key must be 32 bytes."))
        }
        lock.lock()
        defer { lock.unlock() }
        keys[companyId] = key
    }

    public func retrieve(companyId: Company.ID) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return keys[companyId]
    }

    public func delete(companyId: Company.ID) throws {
        lock.lock()
        defer { lock.unlock() }
        keys.removeValue(forKey: companyId)
    }

    public var storedKeyCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return keys.count
    }
}
