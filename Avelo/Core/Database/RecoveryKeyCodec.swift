import Foundation

public enum RecoveryKeyCodec {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    public static func encode(_ key: Data) -> String {
        var output = ""
        var buffer = 0
        var bitsLeft = 0
        for byte in key {
            buffer = (buffer << 8) | Int(byte)
            bitsLeft += 8
            while bitsLeft >= 5 {
                let index = (buffer >> (bitsLeft - 5)) & 31
                output.append(alphabet[index])
                bitsLeft -= 5
            }
        }
        if bitsLeft > 0 {
            let index = (buffer << (5 - bitsLeft)) & 31
            output.append(alphabet[index])
        }
        return stride(from: 0, to: output.count, by: 4).map { start in
            let lower = output.index(output.startIndex, offsetBy: start)
            let upper = output.index(lower, offsetBy: min(4, output.distance(from: lower, to: output.endIndex)))
            return String(output[lower..<upper])
        }.joined(separator: "-")
    }

    public static func decode(_ recoveryKey: String) throws -> Data {
        let cleaned = recoveryKey
            .uppercased()
            .filter { $0 != "-" && !$0.isWhitespace }
        guard !cleaned.isEmpty else {
            throw AppError.validation(.init(code: .internal, message: "Recovery key is empty."))
        }
        var values: [Int] = []
        values.reserveCapacity(cleaned.count)
        for char in cleaned {
            guard let index = alphabet.firstIndex(of: char) else {
                throw AppError.validation(.init(code: .internal, message: "Recovery key contains an invalid character."))
            }
            values.append(index)
        }

        var buffer = 0
        var bitsLeft = 0
        var bytes: [UInt8] = []
        for value in values {
            buffer = (buffer << 5) | value
            bitsLeft += 5
            if bitsLeft >= 8 {
                bytes.append(UInt8((buffer >> (bitsLeft - 8)) & 255))
                bitsLeft -= 8
            }
        }
        let data = Data(bytes)
        guard data.count == 32 else {
            throw AppError.validation(.init(code: .internal, message: "Recovery key must decode to a 32-byte company key."))
        }
        return data
    }
}
