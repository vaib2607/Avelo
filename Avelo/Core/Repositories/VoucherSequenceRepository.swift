import Foundation

public struct VoucherSequenceRepository: Sendable {

    public let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    public func nextNumber(companyId: Company.ID,
                           financialYearId: FinancialYear.ID,
                           typeCode: VoucherType.Code) throws -> String {
        try VoucherNumberGenerator(db: db).next(companyId: companyId,
                                                 financialYearId: financialYearId,
                                                 typeCode: typeCode)
    }
}
