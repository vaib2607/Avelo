import SwiftUI
import Observation

@MainActor
@Observable
public final class BOMsViewModel {

    public var boms: [BOMRepository.BOMListRow] = []
    public var error: AppError?

    public let companyId: Company.ID
    public let db: SQLiteDatabase

    public init(companyId: Company.ID, db: SQLiteDatabase) {
        self.companyId = companyId
        self.db = db
    }

    public func reload() {
        do {
            boms = try BOMService(db: db, companyId: companyId).listBOMs()
            error = nil
        } catch {
            boms = []
            self.error = AppError.wrap(error)
        }
    }
}
