import CryptoKit
import Foundation

public enum RecoveryKeyError: Error, Sendable, Equatable {
    case empty
    case malformed
    case unsupportedVersion(String)
    case checksumMismatch

    public var message: String {
        switch self {
        case .empty:
            return "Recovery key is empty."
        case .malformed:
            return "Recovery key format is invalid. Check the key and try again."
        case .unsupportedVersion(let version):
            return "Recovery key version \(version) is not supported."
        case .checksumMismatch:
            return "Recovery key checksum does not match. Check for a typo and try again."
        }
    }

    var identifier: String {
        switch self {
        case .empty:
            return "empty"
        case .malformed:
            return "malformed"
        case .unsupportedVersion(let version):
            return "unsupported-\(version)"
        case .checksumMismatch:
            return "checksum-mismatch"
        }
    }
}

public enum RecoveryKeyCodec {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    private static let checksumAlphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    private static let canonicalVersion = "AV1"
    private static let payloadLength = 52
    private static let checksumLength = 6
    private static let keyByteCount = 32
    private static let checksumDomain = Data("com.avelo.recovery-key/checksum/AV1\u{0}".utf8)

    /// Emits the current, human-readable recovery-key envelope.
    public static func encode(_ key: Data) -> String {
        let payload = encodeBase32(key)
        let formattedPayload = formatPayload(payload)
        return "\(canonicalVersion)-\(formattedPayload)-\(checksum(for: key))"
    }

    /// Validates an entered key and emits the current canonical AV1 representation.
    /// Legacy unprefixed recovery keys are accepted as input and normalized to AV1.
    public static func canonicalize(_ recoveryKey: String) throws -> String {
        encode(try decode(recoveryKey))
    }

    public static func decode(_ recoveryKey: String) throws -> Data {
        let normalized = normalize(recoveryKey)
        guard !normalized.isEmpty else {
            throw AppError.recoveryKey(.empty)
        }

        if normalized.hasPrefix(canonicalVersion) {
            return try decodeAV1(normalized)
        }

        // A legacy payload can coincidentally begin with AV2 through AV7. Preserve
        // those valid 52-character legacy keys, but reject all actual versioned
        // envelopes that name a version this app does not understand.
        if let version = versionPrefix(in: normalized), normalized.count != payloadLength {
            throw AppError.recoveryKey(.unsupportedVersion(version))
        }

        return try decodeBase32Payload(normalized)
    }

    private static func decodeAV1(_ normalized: String) throws -> Data {
        let expectedLength = canonicalVersion.count + payloadLength + checksumLength
        guard normalized.count == expectedLength else {
            throw AppError.recoveryKey(.malformed)
        }

        let payloadStart = normalized.index(normalized.startIndex, offsetBy: canonicalVersion.count)
        let payloadEnd = normalized.index(payloadStart, offsetBy: payloadLength)
        let payload = String(normalized[payloadStart..<payloadEnd])
        let suppliedChecksum = String(normalized[payloadEnd...])
        guard suppliedChecksum.count == checksumLength,
              suppliedChecksum.allSatisfy({ checksumAlphabet.contains($0) }) else {
            throw AppError.recoveryKey(.malformed)
        }

        let key = try decodeBase32Payload(payload)
        guard checksum(for: key) == suppliedChecksum else {
            throw AppError.recoveryKey(.checksumMismatch)
        }
        return key
    }

    private static func normalize(_ recoveryKey: String) -> String {
        recoveryKey
            .uppercased()
            .filter { $0 != "-" && !$0.isWhitespace }
    }

    private static func versionPrefix(in normalized: String) -> String? {
        guard normalized.count >= canonicalVersion.count,
              normalized.hasPrefix("AV") else {
            return nil
        }
        let end = normalized.index(normalized.startIndex, offsetBy: canonicalVersion.count)
        let version = String(normalized[..<end])
        guard let suffix = version.last, "0123456789".contains(suffix) else {
            return nil
        }
        return version
    }

    private static func encodeBase32(_ key: Data) -> String {
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
            buffer = bitsLeft == 0 ? 0 : buffer & ((1 << bitsLeft) - 1)
        }
        if bitsLeft > 0 {
            let index = (buffer << (5 - bitsLeft)) & 31
            output.append(alphabet[index])
        }
        return output
    }

    private static func decodeBase32Payload(_ payload: String) throws -> Data {
        guard payload.count == payloadLength else {
            throw AppError.recoveryKey(.malformed)
        }

        var values: [Int] = []
        values.reserveCapacity(payload.count)
        for char in payload {
            guard let index = alphabet.firstIndex(of: char) else {
                throw AppError.recoveryKey(.malformed)
            }
            values.append(index)
        }

        // 32 bytes occupy 256 bits, so the final Base32 symbol has four padding
        // bits. Reject non-canonical encodings instead of silently ignoring them.
        guard let last = values.last, (last & 0b0_1111) == 0 else {
            throw AppError.recoveryKey(.malformed)
        }

        var buffer = 0
        var bitsLeft = 0
        var bytes: [UInt8] = []
        bytes.reserveCapacity(keyByteCount)
        for value in values {
            buffer = (buffer << 5) | value
            bitsLeft += 5
            while bitsLeft >= 8 {
                bytes.append(UInt8((buffer >> (bitsLeft - 8)) & 255))
                bitsLeft -= 8
            }
            buffer = bitsLeft == 0 ? 0 : buffer & ((1 << bitsLeft) - 1)
        }
        guard bytes.count == keyByteCount, buffer == 0 else {
            throw AppError.recoveryKey(.malformed)
        }
        return Data(bytes)
    }

    private static func formatPayload(_ payload: String) -> String {
        stride(from: 0, to: payload.count, by: 4).map { start in
            let lower = payload.index(payload.startIndex, offsetBy: start)
            let upper = payload.index(lower, offsetBy: min(4, payload.distance(from: lower, to: payload.endIndex)))
            return String(payload[lower..<upper])
        }.joined(separator: "-")
    }

    private static func checksum(for key: Data) -> String {
        var checksumInput = checksumDomain
        checksumInput.append(key)
        return String(encodeBase32(Data(SHA256.hash(data: checksumInput))).prefix(checksumLength))
    }
}
