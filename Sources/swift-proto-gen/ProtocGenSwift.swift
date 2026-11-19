import Foundation
import SwiftProtobuf
import SwiftProtobufPluginLibrary

func runProtocGenSwift(
    at executable: URL,
    request: Google_Protobuf_Compiler_CodeGeneratorRequest
) throws -> Google_Protobuf_Compiler_CodeGeneratorResponse {
    let requestData: Data = try request.serializedBytes()

    let process = Process()
    process.executableURL = executable
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    try process.run()

    try? input.fileHandleForWriting.write(contentsOf: requestData)
    try? input.fileHandleForWriting.close()
    let responseData = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        throw ToolError("protoc-gen-swift failed with status \(process.terminationStatus)")
    }
    let response = try Google_Protobuf_Compiler_CodeGeneratorResponse(serializedBytes: responseData)
    if response.hasError {
        throw ToolError(response.error)
    }

    guard !response.file.isEmpty else {
        throw ToolError("protoc-gen-swift generated no files")
    }
    return response
}

func write(_ response: Google_Protobuf_Compiler_CodeGeneratorResponse, to directory: URL) throws {
    for file in response.file {
        guard !file.hasInsertionPoint else {
            throw ToolError("\(file.name): insertion points are not supported")
        }
        let url = directory.appendingPathComponent(file.name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(file.content.utf8).write(to: url, options: .atomic)
    }
}
