import Foundation
@testable import Avelo

enum AuditTestKeySupport {
    private static let store = InMemoryCompanyKeyStore()

    static func ensureKey(for companyId: Company.ID) throws {
        AuditChainKeyProvider.registerStore(store)
        if try store.retrieve(companyId: companyId) == nil {
            try store.store(key: store.generateKey(), companyId: companyId)
        }
    }
}
