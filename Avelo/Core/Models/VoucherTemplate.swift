import Foundation

<<<<<<< HEAD
public struct VoucherTemplate: Identifiable, Hashable, Sendable, Codable {
=======
public struct VoucherTemplate: Identifiable, Hashable, Sendable {
>>>>>>> origin/main
    public typealias ID = UUID

    public let id: ID
    public let companyId: Company.ID
    public var name: String
    public var voucherTypeCode: VoucherType.Code
    public var description: String?
    public var templateLinesJSON: String
    public var isActive: Bool
    public let createdAt: Date

    public init(id: ID = UUID(),
                companyId: Company.ID,
                name: String,
                voucherTypeCode: VoucherType.Code,
                description: String? = nil,
                templateLinesJSON: String,
                isActive: Bool = true,
                createdAt: Date = Date()) {
        self.id = id
        self.companyId = companyId
        self.name = name
        self.voucherTypeCode = voucherTypeCode
        self.description = description
        self.templateLinesJSON = templateLinesJSON
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
