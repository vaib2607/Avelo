import Foundation

enum UUIDParsing {

    static func required(_ raw: String, field: String) throws -> UUID {
        guard let value = UUID(uuidString: raw) else {
            throw AppError.database(.rowReadFailed("Invalid UUID in \(field): \(raw)"))
        }
        return value
    }

    static func optional(_ raw: String?, field: String) throws -> UUID? {
        guard let raw, !raw.isEmpty else { return nil }
        return try required(raw, field: field)
    }
}
