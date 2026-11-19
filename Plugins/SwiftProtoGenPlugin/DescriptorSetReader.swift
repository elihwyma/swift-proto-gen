import Foundation

func protoFileNames(inDescriptorSetAt url: URL) throws -> [String] {
    let bytes = try [UInt8](Data(contentsOf: url))
    var names: [String] = []
    do {
        var set = WireReader(bytes[...])
        while let (field, wireType) = try set.nextTag() {
            guard field == 1, wireType == 2 else {
                try set.skip(wireType: wireType)
                continue
            }
            var file = WireReader(try set.readLengthDelimited())
            var name = ""
            while let (field, wireType) = try file.nextTag() {
                if field == 1, wireType == 2 {
                    name = String(decoding: try file.readLengthDelimited(), as: UTF8.self)
                } else {
                    try file.skip(wireType: wireType)
                }
            }
            guard !name.isEmpty else { throw MalformedDescriptorSet() }
            names.append(name)
        }
    } catch is MalformedDescriptorSet {
        throw PluginError(
            "\(url.path(percentEncoded: false)) is not a serialized FileDescriptorSet; create it with "
                + "`protoc --include_imports --descriptor_set_out=<file>.pb` or `buf build -o <file>.pb`"
        )
    }
    return names
}

private struct MalformedDescriptorSet: Error {}

private struct WireReader {
    private var bytes: ArraySlice<UInt8>

    init(_ bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
    }

    mutating func nextTag() throws -> (field: UInt64, wireType: UInt64)? {
        guard !bytes.isEmpty else { return nil }
        let tag = try readVarint()
        guard tag >> 3 != 0 else { throw MalformedDescriptorSet() }
        return (tag >> 3, tag & 0x7)
    }

    mutating func readLengthDelimited() throws -> ArraySlice<UInt8> {
        let length = try readVarint()
        guard length <= bytes.count else { throw MalformedDescriptorSet() }
        defer { bytes = bytes.dropFirst(Int(length)) }
        return bytes.prefix(Int(length))
    }

    mutating func skip(wireType: UInt64) throws {
        switch wireType {
        case 0: _ = try readVarint()
        case 1: try skip(count: 8)
        case 2: _ = try readLengthDelimited()
        case 5: try skip(count: 4)
        default: throw MalformedDescriptorSet()
        }
    }

    private mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        for shift in stride(from: 0, to: 64, by: 7) {
            guard let byte = bytes.popFirst() else { throw MalformedDescriptorSet() }
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
        }
        throw MalformedDescriptorSet()
    }

    private mutating func skip(count: Int) throws {
        guard count <= bytes.count else { throw MalformedDescriptorSet() }
        bytes = bytes.dropFirst(count)
    }
}
