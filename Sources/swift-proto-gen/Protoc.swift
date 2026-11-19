import Foundation

func compileDescriptorSet(
    of sources: [URL],
    protoc: URL,
    protoPaths: [URL],
    scratchDirectory: URL
) throws -> Data {
    try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
    let descriptorSet = scratchDirectory.appendingPathComponent(".swift-proto-gen-\(UUID().uuidString).pb")
    defer { try? FileManager.default.removeItem(at: descriptorSet) }

    let process = Process()
    process.executableURL = protoc
    process.arguments =
        protoPaths.map { "--proto_path=\($0.path)" }
        + ["--include_imports", "--include_source_info", "--descriptor_set_out=\(descriptorSet.path)"]
        + sources.map(\.path)
    try process.run()
    process.waitUntilExit()

    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        throw ToolError("protoc failed with status \(process.terminationStatus)")
    }
    return try Data(contentsOf: descriptorSet)
}
