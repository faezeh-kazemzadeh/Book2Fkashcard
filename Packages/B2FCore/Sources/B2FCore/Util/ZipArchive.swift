import Foundation
#if canImport(Compression)
import Compression
#endif

public enum ZipError: Error, LocalizedError, Equatable {
    case notAZipFile
    case corrupted(String)
    case unsupportedCompression(UInt16)
    case zip64NotSupported
    case entryNotFound(String)
    case checksumMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .notAZipFile: return "The file is not a valid ZIP archive."
        case .corrupted(let reason): return "The archive is damaged (\(reason))."
        case .unsupportedCompression(let method): return "Unsupported ZIP compression method \(method)."
        case .zip64NotSupported: return "ZIP64 archives larger than 4 GB are not supported."
        case .entryNotFound(let name): return "“\(name)” was not found in the archive."
        case .checksumMismatch(let name): return "“\(name)” failed its integrity check."
        }
    }
}

/// Minimal, dependency-free ZIP reader/writer covering what Anki packages,
/// EPUB and DOCX need: stored and DEFLATE entries, UTF-8 names, no encryption.
public enum ZipArchive {

    public struct Entry: Sendable {
        public let path: String
        public let data: Data
        public init(path: String, data: Data) {
            self.path = path
            self.data = data
        }
    }

    // MARK: Writing

    /// Builds a ZIP archive. Entries are DEFLATE-compressed where the platform
    /// supports it and compression actually saves space; otherwise stored.
    public static func create(entries: [Entry], compress: Bool = true) -> Data {
        var output = Data()
        var central = Data()
        let (dosTime, dosDate) = dosTimestamp(Date())

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            var method: UInt16 = 0
            var payload = entry.data
            if compress, let deflated = deflate(entry.data), deflated.count < entry.data.count {
                method = 8
                payload = deflated
            }
            let localOffset = UInt32(output.count)

            var local = Data()
            local.appendLE(UInt32(0x0403_4B50))
            local.appendLE(UInt16(20))          // version needed
            local.appendLE(UInt16(0x0800))      // UTF-8 names
            local.appendLE(method)
            local.appendLE(dosTime)
            local.appendLE(dosDate)
            local.appendLE(crc)
            local.appendLE(UInt32(payload.count))
            local.appendLE(UInt32(entry.data.count))
            local.appendLE(UInt16(nameData.count))
            local.appendLE(UInt16(0))
            local.append(nameData)
            output.append(local)
            output.append(payload)

            central.appendLE(UInt32(0x0201_4B50))
            central.appendLE(UInt16(0x031E))     // made by: UNIX, spec 3.0
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(0x0800))
            central.appendLE(method)
            central.appendLE(dosTime)
            central.appendLE(dosDate)
            central.appendLE(crc)
            central.appendLE(UInt32(payload.count))
            central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt16(nameData.count))
            central.appendLE(UInt16(0))          // extra
            central.appendLE(UInt16(0))          // comment
            central.appendLE(UInt16(0))          // disk
            central.appendLE(UInt16(0))          // internal attrs
            central.appendLE(UInt32(0o100644) << 16) // external attrs: regular file 0644
            central.appendLE(localOffset)
            central.append(nameData)
        }

        let centralOffset = UInt32(output.count)
        output.append(central)
        output.appendLE(UInt32(0x0605_4B50))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(entries.count))
        output.appendLE(UInt16(entries.count))
        output.appendLE(UInt32(central.count))
        output.appendLE(centralOffset)
        output.appendLE(UInt16(0))
        return output
    }

    // MARK: Reading

    public struct CentralEntry: Sendable {
        public let path: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// Lists entries using the central directory (robust to data descriptors).
    public static func listEntries(in data: Data) throws -> [CentralEntry] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipError.notAZipFile }
        var eocd = -1
        let searchStart = max(0, bytes.count - 22 - 65_535)
        var index = bytes.count - 22
        while index >= searchStart {
            if bytes.readLE32(index) == 0x0605_4B50 { eocd = index; break }
            index -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZipFile }
        let total = Int(bytes.readLE16(eocd + 10))
        let cdOffset = Int(bytes.readLE32(eocd + 16))
        if cdOffset == 0xFFFF_FFFF || total == 0xFFFF { throw ZipError.zip64NotSupported }

        var entries: [CentralEntry] = []
        var cursor = cdOffset
        for _ in 0..<total {
            guard cursor + 46 <= bytes.count, bytes.readLE32(cursor) == 0x0201_4B50 else {
                throw ZipError.corrupted("central directory")
            }
            let method = bytes.readLE16(cursor + 10)
            let crc = bytes.readLE32(cursor + 16)
            let compressed = Int(bytes.readLE32(cursor + 20))
            let uncompressed = Int(bytes.readLE32(cursor + 24))
            let nameLength = Int(bytes.readLE16(cursor + 28))
            let extraLength = Int(bytes.readLE16(cursor + 30))
            let commentLength = Int(bytes.readLE16(cursor + 32))
            let localOffset = Int(bytes.readLE32(cursor + 42))
            guard cursor + 46 + nameLength <= bytes.count else { throw ZipError.corrupted("entry name") }
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            entries.append(CentralEntry(path: name, method: method, crc: crc,
                                        compressedSize: compressed, uncompressedSize: uncompressed,
                                        localHeaderOffset: localOffset))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// Extracts a single entry.
    public static func extract(_ entry: CentralEntry, from data: Data) throws -> Data {
        let bytes = data
        let base = bytes.startIndex
        let h = entry.localHeaderOffset
        guard h + 30 <= bytes.count else { throw ZipError.corrupted("local header") }
        let header = [UInt8](bytes[(base + h)..<(base + h + 30)])
        guard header.readLE32(0) == 0x0403_4B50 else { throw ZipError.corrupted("local header signature") }
        let nameLength = Int(header.readLE16(26))
        let extraLength = Int(header.readLE16(28))
        let start = h + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= bytes.count else { throw ZipError.corrupted("entry data") }
        let payload = bytes.subdata(in: (base + start)..<(base + start + entry.compressedSize))

        let output: Data
        switch entry.method {
        case 0: output = payload
        case 8:
            guard let inflated = inflate(payload, expectedSize: entry.uncompressedSize) else {
                throw ZipError.unsupportedCompression(8)
            }
            output = inflated
        default:
            throw ZipError.unsupportedCompression(entry.method)
        }
        guard CRC32.checksum(output) == entry.crc else { throw ZipError.checksumMismatch(entry.path) }
        return output
    }

    /// Extracts every entry into memory. Intended for archives of moderate size.
    public static func extractAll(from data: Data) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for entry in try listEntries(in: data) where !entry.path.hasSuffix("/") {
            result[entry.path] = try extract(entry, from: data)
        }
        return result
    }

    public static func extract(path: String, from data: Data) throws -> Data {
        guard let entry = try listEntries(in: data).first(where: { $0.path == path }) else {
            throw ZipError.entryNotFound(path)
        }
        return try extract(entry, from: data)
    }

    // MARK: DEFLATE

    static func deflate(_ data: Data) -> Data? {
        #if canImport(Compression)
        guard !data.isEmpty else { return nil }
        let capacity = data.count + data.count / 10 + 1024
        var destination = [UInt8](repeating: 0, count: capacity)
        let written = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(&destination, capacity, base, data.count, nil, COMPRESSION_ZLIB)
        }
        return written > 0 ? Data(destination[0..<written]) : nil
        #else
        return nil
        #endif
    }

    static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        #if canImport(Compression)
        if expectedSize == 0 { return Data() }
        var destination = [UInt8](repeating: 0, count: expectedSize)
        let written = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(&destination, expectedSize, base, data.count, nil, COMPRESSION_ZLIB)
        }
        return written == expectedSize ? Data(destination) : nil
        #else
        return nil
        #endif
    }

    private static func dosTimestamp(_ date: Date) -> (UInt16, UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let date = UInt16(max(0, (c.year ?? 1980) - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, date)
    }
}

// MARK: - Little-endian helpers

extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendLE(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((value >> UInt32(shift)) & 0xFF)) }
    }
}

extension Array where Element == UInt8 {
    func readLE16(_ offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func readLE32(_ offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 |
        UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
