import Foundation

// Compile with App/App/NativeVideoPlugin.swift; no GPU or encoder is needed.
@main
struct NativeVideoSizeTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("viper-size-test-\(UUID().uuidString)")
        let job = try NativeVideoJob(directory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(atPath: job.output.path, contents: Data())
        let cached = try job.output.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        precondition(cached == 0)
        let initial = try job.outputSize(finalized: false)
        precondition(initial == 0)
        do {
            _ = try job.outputSize(finalized: true)
            fatalError("Empty output accepted")
        } catch NativeVideoError.invalid {}
        let handle = try FileHandle(forWritingTo: job.output)
        defer { try? handle.close() }
        try handle.write(contentsOf: Data(repeating: 1, count: 4096))
        let stale = try job.output.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        let fresh = try job.outputSize(finalized: true)
        precondition(fresh == 4096)
        print("URL cached size=\(stale); actual size=\(fresh)")
        // Sparse files exercise the ceiling without allocating 256 MiB of storage.
        try handle.truncate(atOffset: UInt64(NativeVideoJob.limit))
        let boundary = try job.outputSize(finalized: true)
        precondition(boundary == NativeVideoJob.limit)
        try handle.truncate(atOffset: UInt64(NativeVideoJob.limit + 1))
        do {
            _ = try job.outputSize(finalized: true)
            fatalError("Oversized output accepted")
        } catch NativeVideoError.tooLarge {}
        do {
            _ = try job.outputSize(finalized: false)
            fatalError("Oversized in-progress output accepted")
        } catch NativeVideoError.tooLarge {}
        try handle.close()
        try FileManager.default.removeItem(at: job.output)
        // Simulate a finalized/faststart file replacing the initial empty file.
        try Data(repeating: 2, count: 8192).write(to: job.output, options: .atomic)
        let replaced = try job.outputSize(finalized: true)
        precondition(replaced == 8192)
        precondition(job.outputDiagnostic.contains("outputBytes=8192"))
        try FileManager.default.removeItem(at: job.output)
        do {
            _ = try job.outputSize(finalized: true)
            fatalError("Missing output accepted")
        } catch is CocoaError {}
        print("PASS: growing, empty, exact limit, over limit (during/final), replaced, missing output, byte diagnostics")
    }
}
