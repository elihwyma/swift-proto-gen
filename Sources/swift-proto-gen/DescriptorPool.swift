import Foundation
import SwiftProtobuf
import SwiftProtobufPluginLibrary

struct DescriptorPool {
    private var files: [String: Google_Protobuf_FileDescriptorProto] = [:]
    private var origins: [String: String] = [:]

    mutating func add(contentsOf url: URL) throws {
        try add(Data(contentsOf: url), from: url.path)
    }

    mutating func add(_ serializedSet: Data, from origin: String) throws {
        let set: Google_Protobuf_FileDescriptorSet
        do {
            set = try Google_Protobuf_FileDescriptorSet(serializedBytes: serializedSet)
        } catch {
            throw ToolError("\(origin): not a serialized FileDescriptorSet (\(error))")
        }

        for var file in set.file {
            file.populateJSONNames()
            guard let existing = files[file.name] else {
                files[file.name] = file
                origins[file.name] = origin
                continue
            }
            guard existing.withoutSourceCodeInfo == file.withoutSourceCodeInfo else {
                throw ToolError(
                    "'\(file.name)' differs between \(origins[file.name]!) and \(origin)"
                )
            }
            if !existing.hasSourceCodeInfo && file.hasSourceCodeInfo {
                files[file.name] = file
            }
        }
    }

    func makeRequest(
        generating names: [String],
        parameter: String
    ) throws -> Google_Protobuf_Compiler_CodeGeneratorRequest {
        var ordered: [Google_Protobuf_FileDescriptorProto] = []
        var finished: Set<String> = []
        var inProgress: Set<String> = []

        func visit(_ name: String, importedBy importer: String?) throws {
            guard !finished.contains(name) else { return }
            guard !inProgress.contains(name) else { throw ToolError("import cycle through '\(name)'") }
            guard let file = files[name] else {
                guard let importer else { throw ToolError("'\(name)' isn't in any input descriptor set") }
                throw ToolError(
                    "'\(importer)' imports '\(name)', which isn't in any input descriptor set; "
                        + "build the .pb files with `protoc --include_imports`"
                )
            }
            inProgress.insert(name)
            for dependency in file.dependency {
                try visit(dependency, importedBy: name)
            }
            inProgress.remove(name)
            finished.insert(name)
            ordered.append(file)
        }

        for name in names {
            try visit(name, importedBy: nil)
        }

        return .with {
            $0.fileToGenerate = names
            $0.parameter = parameter
            $0.protoFile = ordered
            $0.compilerVersion = .with { $0.suffix = "swift-proto-gen" }
        }
    }
}

extension Google_Protobuf_FileDescriptorProto {
    fileprivate var withoutSourceCodeInfo: Self {
        var copy = self
        copy.clearSourceCodeInfo()
        return copy
    }

    fileprivate mutating func populateJSONNames() {
        for index in messageType.indices {
            messageType[index].populateJSONNames()
        }
        for index in `extension`.indices {
            `extension`[index].populateJSONName()
        }
    }
}

extension Google_Protobuf_DescriptorProto {
    fileprivate mutating func populateJSONNames() {
        for index in field.indices {
            field[index].populateJSONName()
        }
        for index in `extension`.indices {
            `extension`[index].populateJSONName()
        }
        for index in nestedType.indices {
            nestedType[index].populateJSONNames()
        }
    }
}

extension Google_Protobuf_FieldDescriptorProto {

    fileprivate mutating func populateJSONName() {
        guard !hasJsonName else { return }
        var result = ""
        var capitalizeNext = false
        for character in name {
            if character == "_" {
                capitalizeNext = true
            } else if capitalizeNext {
                result += character.uppercased()
                capitalizeNext = false
            } else {
                result.append(character)
            }
        }
        jsonName = result
    }
}
