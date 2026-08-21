import Foundation
@preconcurrency import AVFoundation

nonisolated public struct CameraRunRecordingArtifact: Codable, Equatable, Sendable {
    public let url: URL
    public let durationS: Double
    public let frameCount: Int

    public init(url: URL, durationS: Double, frameCount: Int) {
        self.url = url
        self.durationS = durationS
        self.frameCount = frameCount
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

/// A bounded, video-only writer for camera samples.  It intentionally has no
/// microphone or Photos-library side effects; callers explicitly choose those
/// integrations later.  Samples arrive from AVFoundation's serial output
/// queue, while `finish()` waits for that same queue to flush.
nonisolated public final class CameraRunVideoRecorder: @unchecked Sendable {
    public let outputURL: URL

    private let queue = DispatchQueue(label: "kamikaze.camera-run.writer", qos: .userInitiated)
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var startedSession = false
    private var finished = false
    private var frameCount = 0
    private var firstTimestamp: CMTime?
    private var lastTimestamp: CMTime?

    public init(outputURL: URL) {
        self.outputURL = outputURL
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
                let input = AVAssetWriterInput(
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
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else {
                    throw CameraRunVideoRecorderError.cannotAddInput
                }
                writer.add(input)
                guard writer.startWriting() else {
                    throw CameraRunVideoRecorderError.cannotCreateWriter(
                        writer.error?.localizedDescription ?? "startWriting returned false"
                    )
                }
                self.writer = writer
                self.input = input
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
                guard let writer = self.writer, let input = self.input else {
                    continuation.resume(throwing: CameraRunVideoRecorderError.noVideoFrames)
                    return
                }
                guard self.frameCount > 0 else {
                    writer.cancelWriting()
                    continuation.resume(throwing: CameraRunVideoRecorderError.noVideoFrames)
                    return
                }
                input.markAsFinished()
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
                            frameCount: self.frameCount
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
        guard !finished, let writer, let input else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).isValid
                ? Optional(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                : nil else { return }
        guard input.isReadyForMoreMediaData else { return }
        if !startedSession {
            writer.startSession(atSourceTime: timestamp)
            startedSession = true
            firstTimestamp = timestamp
        }
        guard input.append(sampleBuffer) else {
            finished = true
            writer.cancelWriting()
            return
        }
        lastTimestamp = timestamp
        frameCount += 1
    }
}
