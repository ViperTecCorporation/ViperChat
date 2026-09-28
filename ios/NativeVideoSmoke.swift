import Foundation

// Compile alongside App/App/NativeVideoPlugin.swift with macOS swiftc, outside the app target.
// Uses the same AVFoundation exporter; VM results never replace physical iPhone validation.
@main
struct NativeVideoSmoke {
    static func main() async {
        do { try await run() }
        catch { print("EXPORT_FAILED: \(error)"); exit(1) }
    }
    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { fatalError("Usage: smoke input.mp4 output-directory hd|sd") }
        let directory = URL(fileURLWithPath: args[2], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: directory.path) else { fatalError("Output directory must be new") }
        let job = try NativeVideoJob(directory: directory)
        try FileManager.default.removeItem(at: job.input)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: args[1]), to: job.input)
        do {
            let size = try await job.export(quality: args[3], start: 0.5, end: 2.5, mute: false) { value in
                print("progress=\(value)")
            }
            print("EXPORTED \(size) bytes: \(job.output.path)")
        } catch {
            print("STAGE: \(job.stage)")
            throw error
        }
    }
}
