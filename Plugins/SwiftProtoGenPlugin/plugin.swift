import Foundation
import PackagePlugin

@main
struct SwiftProtoGenPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        return try makeBuildCommands(
            files: target.sourceFiles,
            protoRoot: URL(fileURLWithPath: target.directory.string, isDirectory: true),
            workDirectory: context.pluginWorkDirectoryURL,
            tool: context.tool(named:)
        )
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftProtoGenPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        try makeBuildCommands(
            files: target.inputFiles,
            protoRoot: context.xcodeProject.directoryURL,
            workDirectory: context.pluginWorkDirectoryURL,
            tool: context.tool(named:)
        )
    }
}
#endif

struct PluginError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

extension SwiftProtoGenPlugin {
    static let configurationFileName = "swift-proto-gen-config.json"

    func makeBuildCommands(
        files: FileList,
        protoRoot: URL,
        workDirectory: URL,
        tool: (String) throws -> PluginContext.Tool
    ) throws -> [Command] {
        let inputs = files.map(\.url).sorted { $0.path < $1.path }
        let descriptorSets = inputs.filter { $0.pathExtension == "pb" }
        let protoSources = inputs.filter { $0.pathExtension == "proto" }
        guard !descriptorSets.isEmpty || !protoSources.isEmpty else { return [] }

        let configurationFile = files.first { $0.url.lastPathComponent == Self.configurationFileName }?.url
        let configuration = try configurationFile.map(Configuration.init(contentsOf:)) ?? Configuration()

        var protoFiles: [String] = []
        var protoFileByOutput: [String: String] = [:]
        func add(_ protoFile: String) throws {
            guard !protoFile.hasPrefix("google/protobuf/") else { return }
            let output = outputFileName(forProtoFile: protoFile)
            if let existing = protoFileByOutput[output] {
                guard existing == protoFile else {
                    throw PluginError("'\(existing)' and '\(protoFile)' would both generate \(output)")
                }
                return
            }
            protoFileByOutput[output] = protoFile
            protoFiles.append(protoFile)
        }
        for url in descriptorSets {
            for protoFile in try protoFileNames(inDescriptorSetAt: url) {
                try add(protoFile)
            }
        }
        for url in protoSources {
            try add(try protoFileName(of: url, relativeTo: protoRoot))
        }
        guard !protoFiles.isEmpty else { return [] }

        let protocGenSwift = try tool("protoc-gen-swift").url
        var arguments = [
            "--protoc-gen-swift", protocGenSwift.path(percentEncoded: false),
            "--output-dir", workDirectory.path(percentEncoded: false),
        ]
        for parameter in ["FileNaming=PathToUnderscores"] + configuration.generatorParameters {
            arguments += ["--parameter", parameter]
        }
        for protoFile in protoFiles {
            arguments += ["--generate", protoFile]
        }
        var tools = [protocGenSwift]
        if !protoSources.isEmpty {
            let protoc = try protocURL(tool: tool)
            arguments += ["--protoc", protoc.path(percentEncoded: false)]
            arguments += ["--proto-path", protoRoot.path(percentEncoded: false)]
            tools.append(protoc)
        }
        let sources = descriptorSets + protoSources
        arguments += sources.map { $0.path(percentEncoded: false) }

        return [
            .buildCommand(
                displayName: "Generating Swift from \(sources.map(\.lastPathComponent).joined(separator: ", "))",
                executable: try tool("swift-proto-gen").url,
                arguments: arguments,
                inputFiles: sources + tools + (configurationFile.map { [$0] } ?? []),
                outputFiles: protoFiles.map { workDirectory.appending(path: outputFileName(forProtoFile: $0)) }
            )
        ]
    }

    func protoFileName(of url: URL, relativeTo root: URL) throws -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.count > rootComponents.count, components.starts(with: rootComponents) else {
            throw PluginError(
                "\(url.path(percentEncoded: false)) must be inside \(root.path(percentEncoded: false))"
            )
        }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }

    func protocURL(tool: (String) throws -> PluginContext.Tool) throws -> URL {
        if let path = ProcessInfo.processInfo.environment["PROTOC_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        if let protoc = try? tool("protoc") {
            return protoc.url
        }
        for path in ["/opt/homebrew/bin/protoc", "/usr/local/bin/protoc"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw PluginError(
            "compiling .proto files needs protoc; install it (e.g. `brew install protobuf`) "
                + "or set PROTOC_PATH to its location"
        )
    }

    func outputFileName(forProtoFile protoFile: String) -> String {
        let slash = protoFile.lastIndex(of: "/")
        let directory = slash.map { protoFile[...$0] } ?? ""
        let fileName = slash.map { protoFile[protoFile.index(after: $0)...] } ?? protoFile[...]
        let baseName = fileName.lastIndex(of: ".").map { fileName[..<$0] } ?? fileName
        return directory.replacingOccurrences(of: "/", with: "_") + baseName + ".pb.swift"
    }
}

struct Configuration: Decodable {
    enum Visibility: String, Decodable, CaseIterable {
        case `internal` = "Internal"
        case `public` = "Public"
        case `package` = "Package"

        init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let visibility = Self.allCases.first(where: { $0.rawValue.lowercased() == value.lowercased() })
            else {
                throw PluginError(
                    "\(SwiftProtoGenPlugin.configurationFileName): visibility must be Internal, Public or Package, not '\(value)'"
                )
            }
            self = visibility
        }
    }

    var visibility: Visibility?
    var implementationOnlyImports: Bool?
    var useAccessLevelOnImports: Bool?

    init() {}

    init(contentsOf url: URL) throws {
        self = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    var generatorParameters: [String] {
        var parameters: [String] = []
        if let visibility {
            parameters.append("Visibility=\(visibility.rawValue)")
        }
        if let implementationOnlyImports {
            parameters.append("ImplementationOnlyImports=\(implementationOnlyImports)")
        }
        if let useAccessLevelOnImports {
            parameters.append("UseAccessLevelOnImports=\(useAccessLevelOnImports)")
        }
        return parameters
    }
}
