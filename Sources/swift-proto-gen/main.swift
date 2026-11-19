import Foundation

struct ToolError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

struct Options {
    var protocGenSwift: URL
    var outputDirectory: URL
    var parameters: [String]
    var filesToGenerate: [String]
    var descriptorSets: [URL]
    var protoSources: [URL]
    var protoc: URL?
    var protoPaths: [URL]

    init(arguments: [String]) throws {
        var protocGenSwift: String?
        var outputDirectory: String?
        var parameters: [String] = []
        var filesToGenerate: [String] = []
        var inputs: [String] = []
        var protoc: String?
        var protoPaths: [String] = []

        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            func value() throws -> String {
                guard let value = iterator.next() else { throw ToolError("missing value for \(argument)") }
                return value
            }
            switch argument {
            case "--protoc-gen-swift": protocGenSwift = try value()
            case "--output-dir": outputDirectory = try value()
            case "--parameter": parameters.append(try value())
            case "--generate": filesToGenerate.append(try value())
            case "--protoc": protoc = try value()
            case "--proto-path": protoPaths.append(try value())
            case _ where argument.hasPrefix("--"): throw ToolError("unknown option \(argument)")
            default: inputs.append(argument)
            }
        }
        let protoSources = inputs.filter { $0.hasSuffix(".proto") }
        let descriptorSets = inputs.filter { !$0.hasSuffix(".proto") }

        guard let protocGenSwift else { throw ToolError("--protoc-gen-swift is required") }
        guard let outputDirectory else { throw ToolError("--output-dir is required") }
        guard !filesToGenerate.isEmpty else { throw ToolError("at least one --generate is required") }
        guard !inputs.isEmpty else { throw ToolError("no descriptor sets or .proto files given") }
        guard protoSources.isEmpty || protoc != nil else {
            throw ToolError("--protoc is required to compile .proto files")
        }

        self.protocGenSwift = URL(fileURLWithPath: protocGenSwift)
        self.outputDirectory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        self.parameters = parameters
        self.filesToGenerate = filesToGenerate
        self.descriptorSets = descriptorSets.map { URL(fileURLWithPath: $0) }
        self.protoSources = protoSources.map { URL(fileURLWithPath: $0) }
        self.protoc = protoc.map { URL(fileURLWithPath: $0) }
        self.protoPaths = protoPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}

signal(SIGPIPE, SIG_IGN)

do {
    let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
    var pool = DescriptorPool()
    for url in options.descriptorSets {
        try pool.add(contentsOf: url)
    }
    if let protoc = options.protoc, !options.protoSources.isEmpty {
        let descriptorSet = try compileDescriptorSet(
            of: options.protoSources,
            protoc: protoc,
            protoPaths: options.protoPaths,
            scratchDirectory: options.outputDirectory
        )
        try pool.add(descriptorSet, from: "the .proto files compiled by protoc")
    }
    let request = try pool.makeRequest(
        generating: options.filesToGenerate,
        parameter: options.parameters.joined(separator: ",")
    )
    let response = try runProtocGenSwift(at: options.protocGenSwift, request: request)
    try write(response, to: options.outputDirectory)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
