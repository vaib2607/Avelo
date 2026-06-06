import Foundation

public struct Company: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = UUID

    public let id: ID
    public var name: String
    public var addressLine1: String?
    public var addressLine2: String?
    public var city: String?
    public var state: String?
    public var pincode: String?
    public var country: String
    public var gstin: String?
    public var pan: String?
    public var baseCurrency: String
    public var isInventoryEnabled: Bool
    public var inventoryLinkMode: InventoryLinkMode
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: ID = UUID(),
                name: String,
                addressLine1: String? = nil,
                addressLine2: String? = nil,
                city: String? = nil,
                state: String? = nil,
                pincode: String? = nil,
                country: String = "India",
                gstin: String? = nil,
                pan: String? = nil,
                baseCurrency: String = "INR",
                isInventoryEnabled: Bool = false,
                inventoryLinkMode: InventoryLinkMode = .manual,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.addressLine1 = addressLine1
        self.addressLine2 = addressLine2
        self.city = city
        self.state = state
        self.pincode = pincode
        self.country = country
        self.gstin = gstin
        self.pan = pan
        self.baseCurrency = baseCurrency
        self.isInventoryEnabled = isInventoryEnabled
        self.inventoryLinkMode = inventoryLinkMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum InventoryLinkMode: String, CaseIterable, Sendable, Codable, Identifiable {
    case manual
    case autoPrompt
    case autoSilent

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .manual:     return "Manual"
        case .autoPrompt: return "Auto-prompt"
        case .autoSilent: return "Auto-silent"
        }
    }

    public var explanation: String {
        switch self {
        case .manual:     return "Stock and accounting are completely separate. You record stock movements yourself."
        case .autoPrompt: return "After a sales or purchase voucher, Mally asks if you want to record a stock movement."
        case .autoSilent: return "Mally records stock movements automatically on sales or purchase. You can edit or delete them."
        }
    }
}
