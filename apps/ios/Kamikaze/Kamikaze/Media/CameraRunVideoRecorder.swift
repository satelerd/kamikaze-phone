import Foundation
@preconcurrency import AVFoundation

nonisolated public struct CameraRunRecordingArtifact: Codable, Equatable, Sendable {
    public let url: URL
    public let durationS: Double
    public let frameCount: Int
    /// Original AVFoundation presentation timestamps. They share CoreMotion's
    /// monotonic host-clock family and let Camera V2 align video to replay
    /// without guessing from wall-clock dates.
    public let sourceStartTimestampS: Double?
    public let sourceEndTimestampS: Double?

    public init(
        url: URL,
        durationS: Double,
        frameCount: Int,
        sourceStartTimestampS: Double? = nil,
        sourceEndTimestampS: Double? = nil
    ) {
        self.url = url
        self.durationS = durationS
        self.frameCount = frameCount
        self.sourceStartTimestampS = sourceStartTimestampS
        self.sourceEndTimestampS = sourceEndTimestampS
    }
}

nonisolated public enum CameraRunVideoRecorderError: Error, Codable, Equatable, LocalizedError, Sendable {
    case outputExists
    case cannotCreateWriter(String)
    case cannotAddInput
    case writerFailed(String)
    case noVideoFrames
    case alreadyFinished

    public var errorDescription: String? {
        switch self {
        case .outputExists:
            "The requested recording output already exists."
        case let .cannotCreateWriter(reason):
            "Could not create the camera writer: \(reason)"
        case .cannotAddInput:
            "The camera writer could not add a video input."
        case let .writerFailed(reason):
            "The camera writer failed: \(reason)"
        case .noVideoFrames:
            "The camera recording contained no video frames."
        case .alreadyFinished:
            "The camera recording has already been finished."
        }
    }
}

nonisolated private final class CameraRunVideoSampleBox: @unchecked Sendable {
    let value: CMSampleBuffer

    init(_ value: CMSampleBuffer) {
        self.value = value
    }
}

/// A bounded local writer for camera and optional microphone samples. It has
/// no Photos-library or network side effects. Samples arrive from AVFoundation
/// output queues, while `finish()` waits for this writer queue to flush.
nonisolated public final class CameraRunVideoRecorder: @unchecked Sendable {
    public let outputURL: URL
    public let position: CameraRunCameraPosition

    private let queue = DispatchQueue(label: "kamikaze.camera-run.writer", qos: .userInitiated)
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var startedSession = false
    private var finished = false
    private var frameCount = 0
    private var firstTimestamp: CMTime?
    private var lastTimestamp: CMTime?

    public init(
        outputURL: URL,
        position: CameraRunCameraPosition = .rear
    ) {
        self.outputURL = outputURL
        self.position = position
    }

    public func start() throws {
        try queue.sync {
            guard !FileManager.default.fileExists(atPath: outputURL.path) else {
                throw CameraRunVideoRecorderError.outputExists
            }
            do {
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
                let videoInput = AVAssetWriterInput(
                    mediaType: .video,
                    outputSettings: [
                        AVVideoCodecKey: AVVideoCodecType.h264,
                        AVVideoWidthKey: 1_080,
                        AVVideoHeightKey: 1_920,
                        AVVideoCompressionPropertiesKey: [
                            AVVideoAverageBitRateKey: 8_000_000,
                            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                        ]
                    ]
                )
                videoInput.expectsMediaDataInRealTime = true
                videoInput.transform = CameraRunVideoOrientationPolicy.recordingTransform(for: position)
                guard writer.canAdd(videoInput) else {
                    throw CameraRunVideoRecorderError.cannotAddInput
                }
                writer.add(videoInput)

                let audioInput = AVAssetWriterInput(
                    mediaType: .audio,
                    outputSettings: [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVNumberOfChannelsKey: 1,
                        AVSampleRateKey: 44_100,
                        AVEncoderBitRateKey: 128_000
                    ]
                )
                audioInput.expectsMediaDataInRealTime = true
                if writer.canAdd(audioInput) {
                    writer.add(audioInput)
                    self.audioInput = audioInput
                } else {
                    self.audioInput = nil
                }
                guard writer.startWriting() else {
                    throw CameraRunVideoRecorderError.cannotCreateWriter(
                        writer.error?.localizedDescription ?? "startWriting returned false"
                    )
                }
                self.writer = writer
                self.videoInput = videoInput
                self.startedSession = false
                self.finished = false
                self.frameCount = 0
                self.firstTimestamp = nil
                self.lastTimestamp = nil
            } catch let error as CameraRunVideoRecorderError {
                throw error
            } catch {
                throw CameraRunVideoRecorderError.cannotCreateWriter(error.localizedDescription)
            }
        }
    }

    /// Called by the AVCapture output delegate.  It is intentionally
    /// fileprivate so only the capture-session bridge can feed real samples.
    internal func consume(_ sampleBuffer: CMSampleBuffer) {
        let sample = CameraRunVideoSampleBox(sampleBuffer)
        queue.async { [weak self] in
            self?.appendSynchronously(sample.value)
        }
    }

    internal func consumeAudio(_ sampleBuffer: CMSampleBuffer) {
        let sample = CameraRunVideoSampleBox(sampleBuffer)
        queue.async { [weak self] in
            self?.appendAudioSynchronously(sample.value)
        }
    }

    public func finish() async throws -> CameraRunRecordingArtifact {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraRunVideoRecorderError.alreadyFinished)
                    return
                }
                guard !self.finished else {
                    continuation.resume(throwing: CameraRunVideoRecorderError.alreadyFinished)
                    return
                }
                self.finished = true
                guard let writer = self.writer, let videoInput = self.videoInput else {
                    continuation.resume(throwing: CameraRunVideoRecorderError.noVideoFrames)
                    return
                }
                guard self.frameCount > 0 else {
                    writer.cancelWriting()
                    continuation.resume(throwing: CameraRunVideoRecorderError.noVideoFrames)
                    return
                }
                videoInput.markAsFinished()
                self.audioInput?.markAsFinished()
                writer.finishWriting {
                    if self.writer?.status == .completed {
                        let durationS: Double
                        if let first = self.firstTimestamp, let last = self.lastTimestamp {
                            durationS = max(0, CMTimeGetSeconds(last - first))
                        } else {
                            durationS = 0
                        }
                        continuation.resume(returning: CameraRunRecordingArtifact(
                            url: self.outputURL,
                            durationS: durationS,
                            frameCount: self.frameCount,
                            sourceStartTimestampS: self.firstTimestamp.map(CMTimeGetSeconds),
                            sourceEndTimestampS: self.lastTimestamp.map(CMTimeGetSeconds)
                        ))
                    } else {
                        continuation.resume(throwing: CameraRunVideoRecorderError.writerFailed(
                            self.writer?.error?.localizedDescription ?? "finishWriting failed"
                        ))
                    }
                }
            }
        }
    }

    private func appendSynchronously(_ sampleBuffer: CMSampleBuffer) {
        guard !finished, let writer, let videoInput else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).isValid
                ? Optional(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                : nil else { return }
        guard videoInput.isReadyForMoreMediaData else { return }
        startSessionIfNeeded(writer: writer, timestamp: timestamp)
        guard videoInput.append(sampleBuffer) else {
            finished = true
            writer.cancelWriting()
            return
        }
        updateTimestampRange(timestamp)
        frameCount += 1
    }

    private func appendAudioSynchronously(_ sampleBuffer: CMSampleBuffer) {
        guard !finished, let writer, let audioInput else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isValid, audioInput.isReadyForMoreMediaData else { return }
        startSessionIfNeeded(writer: writer, timestamp: timestamp)
        guard audioInput.append(sampleBuffer) else { return }
        updateTimestampRange(timestamp)
    }

    private func startSessionIfNeeded(writer: AVAssetWriter, timestamp: CMTime) {
        guard !startedSession else { return }
        writer.startSession(atSourceTime: timestamp)
        startedSession = true
        firstTimestamp = timestamp
    }

    private func updateTimestampRange(_ timestamp: CMTime) {
        if firstTimestamp == nil || timestamp < firstTimestamp! { firstTimestamp = timestamp }
        if lastTimestamp == nil || timestamp > lastTimestamp! { lastTimestamp = timestamp }
    }
}
