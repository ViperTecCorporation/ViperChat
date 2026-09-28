#if canImport(Capacitor)
import Capacitor
#endif
import AVFoundation
import VideoToolbox

// All bridge IO is serialized. Each export owns its reader/writer and temporary directory.
#if canImport(Capacitor)
@objc(NativeVideoPlugin)
final class NativeVideoPlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "NativeVideoPlugin"
    let jsName = "NativeVideo"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "begin", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "append", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "exportVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "read", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "dispose", returnType: CAPPluginReturnPromise)
    ]
    private let io = DispatchQueue(label: "net.vipertec.video.io")
    private var jobs: [String: NativeVideoJob] = [:]
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("viper-video-export", isDirectory: true)

    override func load() {
        // Only this plugin's scratch directory, never uploads or the photo library.
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @objc func begin(_ call: CAPPluginCall) {
        io.async {
            do {
                let id = UUID().uuidString
                let job = try NativeVideoJob(directory: self.root.appendingPathComponent(id))
                self.jobs[id] = job
                call.resolve(["id": id])
            } catch { call.reject("VIDEO_UNSUPPORTED", nil, error) }
        }
    }

    private func withJob(_ call: CAPPluginCall, action: @escaping (NativeVideoJob) throws -> Void) {
        io.async {
            guard let id = call.getString("id"), let job = self.jobs[id] else {
                call.reject("INVALID_VIDEO"); return
            }
            do { try action(job) }
            catch { call.reject(error.localizedDescription, nil, error) }
        }
    }

    @objc func append(_ call: CAPPluginCall) {
        withJob(call) { job in
            guard !job.running, !job.finished,
                  let text = call.getString("data"), text.count <= 710_000,
                  let data = Data(base64Encoded: text) else { throw NativeVideoError.invalid }
            try job.checkCancellation()
            guard job.inputBytes + data.count <= NativeVideoJob.limit else { throw NativeVideoError.tooLarge }
            let handle = try FileHandle(forWritingTo: job.input)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            job.inputBytes += data.count
            call.resolve()
        }
    }

    @objc func exportVideo(_ call: CAPPluginCall) {
        withJob(call) { job in
            guard !job.running, !job.finished else { throw NativeVideoError.invalid }
            job.running = true
            Task {
                do {
                    let size = try await job.export(
                        quality: call.getString("quality") ?? "hd",
                        start: call.getDouble("start") ?? 0,
                        end: call.getDouble("end"), mute: call.getBool("mute") ?? false,
                        progress: { value in
                            self.notifyListeners("progress", data: ["id": call.getString("id") ?? "", "progress": value])
                        }
                    )
                    self.io.async {
                        job.running = false; job.finished = true
                        call.resolve(["size": size])
                    }
                } catch {
                    self.io.async {
                        job.running = false; job.finished = true
                        let native = error as NSError
                        call.resolve([
                            "error": (error as? NativeVideoError)?.rawValue ?? "VIDEO_UNSUPPORTED",
                            "diagnostic": "\(job.stage): \(native.domain) (\(native.code)); \(job.outputDiagnostic); \(native.localizedDescription)"
                        ])
                    }
                }
            }
        }
    }

    @objc func read(_ call: CAPPluginCall) {
        withJob(call) { job in
            guard job.finished, !job.running, let offset = call.getInt("offset"), offset >= 0 else { throw NativeVideoError.invalid }
            let handle = try FileHandle(forReadingFrom: job.output)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: 512 * 1024) ?? Data()
            call.resolve(["data": data.base64EncodedString()])
        }
    }

    @objc func cancel(_ call: CAPPluginCall) {
        withJob(call) { job in job.cancel(); call.resolve() }
    }

    @objc func dispose(_ call: CAPPluginCall) {
        withJob(call) { job in
            // JS waits for export completion/rejection before disposing.
            guard !job.running else { throw NativeVideoError.invalid }
            try FileManager.default.removeItem(at: job.directory)
            self.jobs.removeValue(forKey: call.getString("id") ?? "")
            call.resolve()
        }
    }
}

#endif

enum NativeVideoError: String, LocalizedError {
    case invalid = "INVALID_VIDEO"
    case unsupported = "VIDEO_UNSUPPORTED"
    case tooLarge = "VIDEO_TOO_LARGE"
    case cancelled = "AbortError"
    var errorDescription: String? { rawValue }
}

final class NativeVideoJob {
    static let limit = 256 * 1024 * 1024
    let directory: URL
    let input: URL
    let output: URL
    var inputBytes = 0
    var running = false
    var finished = false
    var stage = "metadata"
    var outputDiagnostic = "outputBytes=not-measured"
    private let lock = NSLock()
    private var cancelled = false

    init(directory: URL) throws {
        self.directory = directory
        input = directory.appendingPathComponent("input.mp4")
        output = directory.appendingPathComponent("output.mp4")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: input.path, contents: nil) else { throw NativeVideoError.invalid }
    }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func checkCancellation() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw NativeVideoError.cancelled }
    }

    // URL resource values can retain the size observed before the writer finished.
    // Stat the path afresh, including after faststart has replaced/rearranged the file.
    func outputSize(finalized: Bool) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        guard let number = attributes[.size] as? NSNumber else { throw NativeVideoError.invalid }
        let bytes = number.intValue
        outputDiagnostic = "outputBytes=\(bytes); limitBytes=\(Self.limit)"
        guard bytes <= Self.limit else { throw NativeVideoError.tooLarge }
        if finalized && bytes <= 0 { throw NativeVideoError.invalid }
        return bytes
    }

    func export(quality: String, start: Double, end: Double?, mute: Bool,
                progress: @escaping (Double) -> Void) async throws -> Int {
        try checkCancellation()
        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw NativeVideoError.invalid }
        let duration = try await asset.load(.duration).seconds
        let stop = (end ?? 0) > 0 ? end! : duration
        guard start.isFinite, stop.isFinite, start >= 0, stop > start, stop <= duration + 0.05 else { throw NativeVideoError.invalid }
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 60000),
                                duration: CMTime(seconds: min(stop, duration) - start, preferredTimescale: 60000))
        let transform = try await track.load(.preferredTransform)
        let naturalSize = try await track.load(.naturalSize)
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let sd = quality == "sd"
        let scale = min(1, (sd ? 854.0 : 1280.0) / max(bounds.width, bounds.height),
                        (sd ? 480.0 : 720.0) / min(bounds.width, bounds.height))
        let width = max(2, Int(bounds.width * scale) / 2 * 2)
        let height = max(2, Int(bounds.height * scale) / 2 * 2)
        let nominalFPS = try await track.load(.nominalFrameRate)
        guard nominalFPS > 0 else { throw NativeVideoError.invalid }
        let fps = min(30.0, Double(nominalFPS))
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: width, height: height)
        composition.frameDuration = CMTime(seconds: 1 / fps, preferredTimescale: 60000)
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let normalized = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: Double(width) / bounds.width, y: Double(height) / bounds.height))
        layer.setTransform(normalized, at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]

        stage = "reader"
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        // AVFoundation renders/converts actual pixels into limited-range NV12, not metadata-only relabeling.
        let video = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        video.videoComposition = composition
        video.alwaysCopiesSampleData = false
        guard reader.canAdd(video) else { throw NativeVideoError.unsupported }
        reader.add(video)
        stage = "writer-settings"
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let bitrate = sd ? 1_200_000 : 2_500_000
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoPixelAspectRatioKey: [AVVideoPixelAspectRatioHorizontalSpacingKey: 1, AVVideoPixelAspectRatioVerticalSpacingKey: 1],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(Double(bitrate) * 0.8),
                AVVideoProfileLevelKey: kVTProfileLevel_H264_Main_4_0,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                kVTCompressionPropertyKey_DataRateLimits as String: [bitrate / 8, 1]
            ]
        ]
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else { throw NativeVideoError.unsupported }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        guard writer.canAdd(videoInput) else { throw NativeVideoError.unsupported }
        writer.add(videoInput)
        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        stage = "audio-settings"
        if !mute, let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let formats = try await audioTrack.load(.formatDescriptions)
            let sourceChannels = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame } ?? 2
            let channels = min(2, max(1, Int(sourceChannels)))
            let audio = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false
            ])
            audio.alwaysCopiesSampleData = false
            let sink = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: sd ? 64000 : 96000
            ])
            guard reader.canAdd(audio), writer.canAdd(sink) else { throw NativeVideoError.unsupported }
            reader.add(audio); writer.add(sink)
            audioOutput = audio; audioInput = sink
        }
        stage = "start"
        guard writer.startWriting(), reader.startReading() else { throw writer.error ?? reader.error ?? NativeVideoError.unsupported }
        writer.startSession(atSourceTime: range.start)
        do {
            stage = "encode"
            var videoDone = false
            var audioDone = audioOutput == nil
            var lastProgress = -1.0
            while !videoDone || !audioDone {
                try checkCancellation()
                guard writer.status == .writing else { throw writer.error ?? NativeVideoError.unsupported }
                if !videoDone, videoInput.isReadyForMoreMediaData {
                    try autoreleasepool {
                        if let sample = video.copyNextSampleBuffer() {
                            guard let pixels = CMSampleBufferGetImageBuffer(sample),
                                  CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                  videoInput.append(sample) else { throw writer.error ?? NativeVideoError.unsupported }
                            let value = max(0, min(1, (CMSampleBufferGetPresentationTimeStamp(sample).seconds - start) / range.duration.seconds))
                            if value - lastProgress >= 0.01 {
                                progress(value); lastProgress = value
                                _ = try outputSize(finalized: false)
                            }
                        } else { videoInput.markAsFinished(); videoDone = true }
                    }
                }
                if !audioDone, let source = audioOutput, let sink = audioInput, sink.isReadyForMoreMediaData {
                    try autoreleasepool {
                        if let sample = source.copyNextSampleBuffer() {
                            guard sink.append(sample) else { throw writer.error ?? NativeVideoError.unsupported }
                        } else { sink.markAsFinished(); audioDone = true }
                    }
                }
                if reader.status == .failed { throw reader.error ?? NativeVideoError.invalid }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            stage = "finalize"
            guard reader.status == .completed else { throw reader.error ?? NativeVideoError.invalid }
            writer.endSession(atSourceTime: CMTimeRangeGetEnd(range))
            await writer.finishWriting()
            try checkCancellation()
            guard writer.status == .completed else { throw writer.error ?? NativeVideoError.unsupported }
            return try outputSize(finalized: true)
        } catch {
            reader.cancelReading(); writer.cancelWriting()
            throw error
        }
    }
}
