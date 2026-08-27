import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Photos
import UIKit
@preconcurrency import AVFoundation

nonisolated public struct CameraRunVideoSource: Equatable, Sendable {
    public let position: CameraRunCameraPosition
    public let url: URL

    public init(position: CameraRunCameraPosition, url: URL) {
        self.position = position
        self.url = url
    }
}

nonisolated public struct CameraRunVideoCompositionRequest: Sendable {
    public let sources: [CameraRunVideoSource]
    public let edit: CameraRunEdit
    public let outputURL: URL
    public let frameRate: Int

    public init(
        sources: [CameraRunVideoSource],
        edit: CameraRunEdit,
        outputURL: URL,
        frameRate: Int = 30
    ) {
        self.sources = sources
        self.edit = edit
        self.outputURL = outputURL
        self.frameRate = frameRate
    }
}

nonisolated public struct CameraRunVideoCompositionArtifact: Equatable, Sendable {
    public let url: URL
    public let durationS: Double
    public let canvas: CGSize
    public let sourceCount: Int

    public init(url: URL, durationS: Double, canvas: CGSize, sourceCount: Int) {
        self.url = url
        self.durationS = durationS
        self.canvas = canvas
        self.sourceCount = sourceCount
    }
}

nonisolated public enum CameraRunVideoCompositionError: Error, Equatable, LocalizedError, Sendable {
    case noSources
    case tooManySources
    case invalidCanvas
    case invalidFrameRate
    case missingVideoTrack(String)
    case invalidDuration
    case invalidTrim
    case cannotAddTrack
    case outputExists
    case cannotCreateExporter
    case exportFailed(String)
    case exportCancelled
    case photosPermissionDenied
    case photosSaveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noSources: "There is no camera video to render."
        case .tooManySources: "Camera Run currently supports at most two camera tracks."
        case .invalidCanvas: "The export canvas is invalid."
        case .invalidFrameRate: "The export frame rate must be between 1 and 60 FPS."
        case let .missingVideoTrack(name): "The \(name) clip has no readable video track."
        case .invalidDuration: "The camera clips do not share a usable duration."
        case .invalidTrim: "The selected trim has no video."
        case .cannotAddTrack: "The camera tracks could not be added to the final composition."
        case .outputExists: "The rendered output already exists."
        case .cannotCreateExporter: "The device could not create a video exporter."
        case let .exportFailed(reason): "The final Camera Run could not be rendered: \(reason)"
        case .exportCancelled: "Camera Run export was cancelled."
        case .photosPermissionDenied: "Allow Add Photos access to save the finished Camera Run."
        case let .photosSaveFailed(reason): "The finished Camera Run could not be saved to Photos: \(reason)"
        }
    }
}

/// Pure layout math kept separate from AVFoundation so every caller and test
/// uses the same source ordering and rectangles.
nonisolated public enum CameraRunVideoLayoutPlanner {
    public static func rectangles(
        preset: CameraRunLayoutPreset,
        canvas: CGSize,
        positions: [CameraRunCameraPosition]
    ) -> [CameraRunCameraPosition: CGRect] {
        guard canvas.width > 0, canvas.height > 0 else { return [:] }
        guard positions.count > 1 else {
            return positions.first.map { [$0: CGRect(origin: .zero, size: canvas)] } ?? [:]
        }

        switch preset {
        case .vertical:
            let halfHeight = canvas.height / 2
            return [
                .rear: CGRect(x: 0, y: halfHeight, width: canvas.width, height: halfHeight),
                .front: CGRect(x: 0, y: 0, width: canvas.width, height: halfHeight)
            ]
        case .pictureInPicture:
            let inset = canvas.width * 0.045
            let pipWidth = canvas.width * 0.35
            let pipHeight = pipWidth * 16 / 9
            return [
                .rear: CGRect(origin: .zero, size: canvas),
                .front: CGRect(
                    x: canvas.width - pipWidth - inset,
                    y: canvas.height - pipHeight - inset,
                    width: pipWidth,
                    height: pipHeight
                )
            ]
        }
    }
}

nonisolated public enum CameraRunReplayTransitionStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case cut
    case crossDissolve
}

/// Non-destructive description of where the measured replay replaces the
/// camera footage. Progress values address the already-trimmed camera edit:
/// camera plays until `entryProgress`, the replay takes the full canvas, then
/// camera resumes at `resumeProgress` so both the intro and reaction survive.
nonisolated public struct CameraRunReplayTransition: Codable, Equatable, Sendable {
    public var entryProgress: Double
    public var resumeProgress: Double
    public var style: CameraRunReplayTransitionStyle
    public var durationS: Double

    public init(
        entryProgress: Double = 0.42,
        resumeProgress: Double = 0.68,
        style: CameraRunReplayTransitionStyle = .crossDissolve,
        durationS: Double = 0.25
    ) {
        self.entryProgress = entryProgress
        self.resumeProgress = resumeProgress
        self.style = style
        self.durationS = durationS
    }

    public static let endCard = CameraRunReplayTransition(
        entryProgress: 1,
        resumeProgress: 1,
        style: .cut,
        durationS: 0
    )
}

/// Exact timing math used by the compositor and editor UI. Keeping it pure
/// makes the authored cut inspectable without decoding or rewriting sources.
nonisolated public struct CameraRunReplayTimelinePlan: Equatable, Sendable {
    public let entryProgress: Double
    public let resumeProgress: Double
    public let cameraIntroDurationS: Double
    public let cameraSkippedDurationS: Double
    public let cameraOutroDurationS: Double
    public let replayStartS: Double
    public let cameraOutroStartS: Double
    public let entryTransitionDurationS: Double
    public let exitTransitionDurationS: Double
    public let outputDurationS: Double

    public static func make(
        cameraDurationS: Double,
        replayDurationS: Double,
        transition: CameraRunReplayTransition
    ) throws -> CameraRunReplayTimelinePlan {
        guard cameraDurationS.isFinite, cameraDurationS > 0,
              replayDurationS.isFinite, replayDurationS > 0 else {
            throw CameraRunVideoCompositionError.invalidDuration
        }

        let entry = min(1, max(0, transition.entryProgress.isFinite ? transition.entryProgress : 0))
        let resume = min(1, max(entry, transition.resumeProgress.isFinite ? transition.resumeProgress : entry))
        let intro = cameraDurationS * entry
        let skipped = cameraDurationS * (resume - entry)
        let outro = cameraDurationS * (1 - resume)
        let requestedDissolve = transition.style == .crossDissolve
            ? max(0, transition.durationS.isFinite ? transition.durationS : 0)
            : 0
        // Reserve half the replay for each possible edge so two dissolves can
        // never overlap each other, even on a very short measured replay.
        let entryDissolve = min(requestedDissolve, intro, replayDurationS / 2)
        let exitDissolve = min(requestedDissolve, outro, replayDurationS / 2)
        let replayStart = intro - entryDissolve
        let outroStart = replayStart + replayDurationS - exitDissolve
        let total = outroStart + outro

        return CameraRunReplayTimelinePlan(
            entryProgress: entry,
            resumeProgress: resume,
            cameraIntroDurationS: intro,
            cameraSkippedDurationS: skipped,
            cameraOutroDurationS: outro,
            replayStartS: replayStart,
            cameraOutroStartS: outroStart,
            entryTransitionDurationS: entryDissolve,
            exitTransitionDurationS: exitDissolve,
            outputDurationS: total
        )
    }
}

/// Pure timing contract for the automatic trick speed ramp. `playbackRate`
/// describes source speed (0.35 means the measured window takes 1 / 0.35 as
/// long in the finished clip); intro and reaction remain untouched at 1x.
nonisolated struct CameraRunSpeedRampPlan: Equatable, Sendable {
    let sourceRange: CameraRunTrim
    let playbackRate: Double
    let outputDurationS: Double

    static func make(
        sourceDurationS: Double,
        sourceRange: CameraRunTrim,
        playbackRate: Double
    ) throws -> CameraRunSpeedRampPlan {
        guard sourceDurationS.isFinite, sourceDurationS > 0,
              playbackRate.isFinite, playbackRate > 0, playbackRate <= 1 else {
            throw CameraRunVideoCompositionError.invalidDuration
        }
        let range = sourceRange.clamped(to: sourceDurationS)
        guard range.durationS > 0 else {
            throw CameraRunVideoCompositionError.invalidTrim
        }
        return CameraRunSpeedRampPlan(
            sourceRange: range,
            playbackRate: playbackRate,
            outputDurationS: sourceDurationS + range.durationS * (1 / playbackRate - 1)
        )
    }
}

@MainActor
public final class CameraRunVideoComposer {
    private struct LoadedSource {
        let source: CameraRunVideoSource
        let asset: AVURLAsset
        let track: AVAssetTrack
        let audioTrack: AVAssetTrack?
        let duration: CMTime
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
    }

    public init() {}

    public func export(
        _ request: CameraRunVideoCompositionRequest
    ) async throws -> CameraRunVideoCompositionArtifact {
        guard !request.sources.isEmpty else { throw CameraRunVideoCompositionError.noSources }
        guard request.sources.count <= 2 else { throw CameraRunVideoCompositionError.tooManySources }
        guard request.edit.layout.width > 0, request.edit.layout.height > 0 else {
            throw CameraRunVideoCompositionError.invalidCanvas
        }
        guard (1...60).contains(request.frameRate) else {
            throw CameraRunVideoCompositionError.invalidFrameRate
        }
        guard !FileManager.default.fileExists(atPath: request.outputURL.path) else {
            throw CameraRunVideoCompositionError.outputExists
        }

        let loaded = try await load(request.sources)
        let commonDuration = loaded.map(\.duration).min(by: { $0 < $1 }) ?? .zero
        let commonDurationS = CMTimeGetSeconds(commonDuration)
        guard commonDurationS.isFinite, commonDurationS > 0 else {
            throw CameraRunVideoCompositionError.invalidDuration
        }
        let trim = request.edit.trim.clamped(to: commonDurationS)
        guard trim.durationS > 0 else { throw CameraRunVideoCompositionError.invalidTrim }

        try FileManager.default.createDirectory(
            at: request.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let composition = AVMutableComposition()
        let sourceRange = CMTimeRange(
            start: CMTime(seconds: trim.startS, preferredTimescale: 600),
            duration: CMTime(seconds: trim.durationS, preferredTimescale: 600)
        )
        let canvas = CGSize(
            width: request.edit.layout.width,
            height: request.edit.layout.height
        )
        let positions = loaded.map(\.source.position)
        let rectangles = CameraRunVideoLayoutPlanner.rectangles(
            preset: request.edit.layout.preset,
            canvas: canvas,
            positions: positions
        )

        var instructionsByPosition: [CameraRunCameraPosition: AVMutableVideoCompositionLayerInstruction] = [:]
        for source in loaded {
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw CameraRunVideoCompositionError.cannotAddTrack
            }
            do {
                try compositionTrack.insertTimeRange(sourceRange, of: source.track, at: .zero)
            } catch {
                throw CameraRunVideoCompositionError.exportFailed(error.localizedDescription)
            }
            guard let destination = rectangles[source.source.position] else { continue }
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
            layer.setTransform(
                Self.aspectFillTransform(
                    naturalSize: source.naturalSize,
                    preferredTransform: source.preferredTransform,
                    destination: destination
                ),
                at: .zero
            )
            instructionsByPosition[source.source.position] = layer
        }

        // The microphone is duplicated into each original camera file so
        // either source remains independently shareable. A composition must
        // select it once — never mix the same microphone twice.
        if let sourceAudio = loaded.first(where: { $0.audioTrack != nil })?.audioTrack,
           let audioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try audioTrack.insertTimeRange(sourceRange, of: sourceAudio, at: .zero)
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: sourceRange.duration)
        // First instruction is visually frontmost. Keep the selfie camera on
        // top for PiP, while both tracks remain equally visible when stacked.
        instruction.layerInstructions = [
            instructionsByPosition[.front],
            instructionsByPosition[.rear]
        ].compactMap { $0 }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(request.frameRate))
        videoComposition.instructions = [instruction]

        let visibleCaptions = request.edit.captions.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && min(trim.endS, $0.endS) > max(trim.startS, $0.startS)
        }
        let baseOutputURL = visibleCaptions.isEmpty
            ? request.outputURL
            : request.outputURL.deletingLastPathComponent().appending(
                path: ".camera-base-\(UUID().uuidString).mp4"
            )

        try await exportComposition(
            composition,
            videoComposition: videoComposition,
            outputURL: baseOutputURL,
            stage: "camera-layout"
        )

        if !visibleCaptions.isEmpty {
            do {
                try await burnCaptions(
                    inputURL: baseOutputURL,
                    outputURL: request.outputURL,
                    captions: visibleCaptions,
                    trim: trim,
                    canvas: canvas,
                    frameRate: request.frameRate
                )
                try? FileManager.default.removeItem(at: baseOutputURL)
            } catch {
                try? FileManager.default.removeItem(at: baseOutputURL)
                if let error = error as? CameraRunVideoCompositionError { throw error }
                throw CameraRunVideoCompositionError.exportFailed(error.localizedDescription)
            }
        }

        return CameraRunVideoCompositionArtifact(
            url: request.outputURL,
            durationS: trim.durationS,
            canvas: canvas,
            sourceCount: loaded.count
        )
    }

    public func saveToPhotos(_ artifact: CameraRunVideoCompositionArtifact) async throws {
        guard FileManager.default.isReadableFile(atPath: artifact.url.path) else {
            throw CameraRunVideoCompositionError.photosSaveFailed("The rendered MP4 is no longer readable.")
        }
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status: PHAuthorizationStatus
        if current == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            status = current
        }
        guard status == .authorized || status == .limited else {
            throw CameraRunVideoCompositionError.photosPermissionDenied
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: artifact.url, options: options)
            }
        } catch {
            throw CameraRunVideoCompositionError.photosSaveFailed(error.localizedDescription)
        }
    }

    /// Adds the real microphone track to an already-rendered 3D replay. The
    /// video pixels remain untouched; only a new MP4 container is written.
    public func attachAudio(
        videoURL: URL,
        audioSourceURL: URL,
        audioStartS: Double,
        outputURL: URL,
        canvas: CGSize
    ) async throws -> CameraRunVideoCompositionArtifact {
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CameraRunVideoCompositionError.outputExists
        }
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioSourceURL)
        guard let videoSource = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw CameraRunVideoCompositionError.missingVideoTrack("3D replay")
        }
        guard let audioSource = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            // A video-only capture is still a valid result when microphone
            // permission was denied. Preserve it instead of failing export.
            try FileManager.default.copyItem(at: videoURL, to: outputURL)
            let duration = try await videoAsset.load(.duration).seconds
            return CameraRunVideoCompositionArtifact(
                url: outputURL,
                durationS: max(0, duration),
                canvas: canvas,
                sourceCount: 1
            )
        }

        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let boundedAudioStart = min(
            max(0, audioStartS),
            max(0, audioDuration.seconds)
        )
        let availableAudio = max(0, audioDuration.seconds - boundedAudioStart)
        let durationS = max(0, videoDuration.seconds)
        let audioSpanS = min(durationS, availableAudio)
        guard durationS > 0 else { throw CameraRunVideoCompositionError.invalidDuration }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw CameraRunVideoCompositionError.cannotAddTrack }

        let outputRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: durationS, preferredTimescale: 600)
        )
        try videoTrack.insertTimeRange(outputRange, of: videoSource, at: .zero)
        videoTrack.preferredTransform = try await videoSource.load(.preferredTransform)
        if audioSpanS > 0 {
            try audioTrack.insertTimeRange(
                CMTimeRange(
                    start: CMTime(seconds: boundedAudioStart, preferredTimescale: 600),
                    duration: CMTime(seconds: audioSpanS, preferredTimescale: 600)
                ),
                of: audioSource,
                at: .zero
            )
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw CameraRunVideoCompositionError.cannotCreateExporter }
        exporter.shouldOptimizeForNetworkUse = true
        do {
            try await exporter.export(to: outputURL, as: .mp4)
        } catch {
            throw CameraRunVideoCompositionError.exportFailed(Self.exportDiagnostic(error: error))
        }
        return CameraRunVideoCompositionArtifact(
            url: outputURL,
            durationS: durationS,
            canvas: canvas,
            sourceCount: 1
        )
    }

    /// Backwards-compatible end-card export. New Camera Run edits should call
    /// `composeReplay` with their authored transition.
    public func appendReplay(
        cameraArtifact: CameraRunVideoCompositionArtifact,
        replayArtifact: ReplayVideoArtifact,
        outputURL: URL,
        frameRate: Int = 30
    ) async throws -> CameraRunVideoCompositionArtifact {
        try await composeReplay(
            cameraArtifact: cameraArtifact,
            replayArtifact: replayArtifact,
            transition: .endCard,
            outputURL: outputURL,
            frameRate: frameRate
        )
    }

    /// Builds a social-first three-act edit: camera intro, measured 3D replay,
    /// camera reaction. Camera and replay artifacts remain untouched; only a
    /// new composition is written. Audio is deliberately not synthesized or
    /// replaced by this video-only pass.
    public func composeReplay(
        cameraArtifact: CameraRunVideoCompositionArtifact,
        replayArtifact: ReplayVideoArtifact,
        transition: CameraRunReplayTransition,
        outputURL: URL,
        frameRate: Int = 30
    ) async throws -> CameraRunVideoCompositionArtifact {
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CameraRunVideoCompositionError.outputExists
        }
        guard (1...60).contains(frameRate) else {
            throw CameraRunVideoCompositionError.invalidFrameRate
        }
        let canvas = cameraArtifact.canvas
        guard canvas.width > 0, canvas.height > 0 else {
            throw CameraRunVideoCompositionError.invalidCanvas
        }

        let loaded = try await load([
            CameraRunVideoSource(position: .rear, url: cameraArtifact.url),
            CameraRunVideoSource(position: .front, url: replayArtifact.url)
        ])
        guard let camera = loaded.first(where: { $0.source.position == .rear }),
              let replay = loaded.first(where: { $0.source.position == .front }) else {
            throw CameraRunVideoCompositionError.noSources
        }
        let cameraDurationS = CMTimeGetSeconds(camera.duration)
        let replayDurationS = CMTimeGetSeconds(replay.duration)
        let plan = try CameraRunReplayTimelinePlan.make(
            cameraDurationS: cameraDurationS,
            replayDurationS: replayDurationS,
            transition: transition
        )

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let composition = AVMutableComposition()
        guard let cameraIntroTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let replayTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let cameraOutroTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CameraRunVideoCompositionError.cannotAddTrack
        }

        do {
            if plan.cameraIntroDurationS > 0 {
                try cameraIntroTrack.insertTimeRange(
                    CMTimeRange(
                        start: .zero,
                        duration: CMTime(seconds: plan.cameraIntroDurationS, preferredTimescale: 600)
                    ),
                    of: camera.track,
                    at: .zero
                )
            }
            try replayTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: replay.duration),
                of: replay.track,
                at: CMTime(seconds: plan.replayStartS, preferredTimescale: 600)
            )
            if plan.cameraOutroDurationS > 0 {
                try cameraOutroTrack.insertTimeRange(
                    CMTimeRange(
                        start: CMTime(seconds: cameraDurationS * plan.resumeProgress, preferredTimescale: 600),
                        duration: CMTime(seconds: plan.cameraOutroDurationS, preferredTimescale: 600)
                    ),
                    of: camera.track,
                    at: CMTime(seconds: plan.cameraOutroStartS, preferredTimescale: 600)
                )
            }

            if let sourceAudio = camera.audioTrack,
               let outputAudio = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                // Preserve the real intro, throw sound/voice and reaction in
                // the same three-act timing as the visual Story Cut. The
                // replaced camera window is time-scaled to the measured 3D
                // span; no synthetic sound is introduced.
                let introAudioDurationS = max(0, plan.replayStartS)
                if introAudioDurationS > 0 {
                    try outputAudio.insertTimeRange(
                        CMTimeRange(
                            start: .zero,
                            duration: CMTime(seconds: introAudioDurationS, preferredTimescale: 600)
                        ),
                        of: sourceAudio,
                        at: .zero
                    )
                }

                let middleSourceStartS = introAudioDurationS
                let middleSourceEndS = cameraDurationS * plan.resumeProgress
                let middleSourceDurationS = max(0, middleSourceEndS - middleSourceStartS)
                let middleOutputDurationS = max(0, plan.cameraOutroStartS - plan.replayStartS)
                if middleSourceDurationS > 0, middleOutputDurationS > 0 {
                    let insertedRange = CMTimeRange(
                        start: CMTime(seconds: middleSourceStartS, preferredTimescale: 600),
                        duration: CMTime(seconds: middleSourceDurationS, preferredTimescale: 600)
                    )
                    try outputAudio.insertTimeRange(
                        insertedRange,
                        of: sourceAudio,
                        at: CMTime(seconds: plan.replayStartS, preferredTimescale: 600)
                    )
                    outputAudio.scaleTimeRange(
                        CMTimeRange(
                            start: CMTime(seconds: plan.replayStartS, preferredTimescale: 600),
                            duration: insertedRange.duration
                        ),
                        toDuration: CMTime(seconds: middleOutputDurationS, preferredTimescale: 600)
                    )
                }

                if plan.cameraOutroDurationS > 0 {
                    try outputAudio.insertTimeRange(
                        CMTimeRange(
                            start: CMTime(
                                seconds: cameraDurationS * plan.resumeProgress,
                                preferredTimescale: 600
                            ),
                            duration: CMTime(
                                seconds: plan.cameraOutroDurationS,
                                preferredTimescale: 600
                            )
                        ),
                        of: sourceAudio,
                        at: CMTime(seconds: plan.cameraOutroStartS, preferredTimescale: 600)
                    )
                }
            }
        } catch {
            throw CameraRunVideoCompositionError.exportFailed(error.localizedDescription)
        }

        let destination = CGRect(origin: .zero, size: canvas)
        let cameraTransform = Self.aspectFillTransform(
            naturalSize: camera.naturalSize,
            preferredTransform: camera.preferredTransform,
            destination: destination
        )
        let replayTransform = Self.aspectFillTransform(
            naturalSize: replay.naturalSize,
            preferredTransform: replay.preferredTransform,
            destination: destination
        )

        func layer(
            track: AVCompositionTrack,
            transform: CGAffineTransform,
            transformTimeS: Double
        ) -> AVMutableVideoCompositionLayerInstruction {
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(
                transform,
                at: CMTime(seconds: transformTimeS, preferredTimescale: 600)
            )
            return layer
        }

        var instructions: [AVMutableVideoCompositionInstruction] = []
        func addInstruction(startS: Double, durationS: Double, layers: [AVVideoCompositionLayerInstruction]) {
            guard durationS > 0 else { return }
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(
                start: CMTime(seconds: startS, preferredTimescale: 600),
                duration: CMTime(seconds: durationS, preferredTimescale: 600)
            )
            instruction.layerInstructions = layers
            instructions.append(instruction)
        }

        let entryTransitionStartS = plan.replayStartS
        addInstruction(
            startS: 0,
            durationS: entryTransitionStartS,
            layers: [layer(track: cameraIntroTrack, transform: cameraTransform, transformTimeS: 0)]
        )
        if plan.entryTransitionDurationS > 0 {
            let range = CMTimeRange(
                start: CMTime(seconds: entryTransitionStartS, preferredTimescale: 600),
                duration: CMTime(seconds: plan.entryTransitionDurationS, preferredTimescale: 600)
            )
            let introTransitionLayer = layer(
                track: cameraIntroTrack,
                transform: cameraTransform,
                transformTimeS: 0
            )
            let replayTransitionLayer = layer(
                track: replayTrack,
                transform: replayTransform,
                transformTimeS: plan.replayStartS
            )
            introTransitionLayer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: range)
            replayTransitionLayer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: range)
            addInstruction(
                startS: entryTransitionStartS,
                durationS: plan.entryTransitionDurationS,
                layers: [replayTransitionLayer, introTransitionLayer]
            )
        }

        let replaySoloStartS = plan.cameraIntroDurationS
        let replaySoloEndS = plan.cameraOutroStartS
        addInstruction(
            startS: replaySoloStartS,
            durationS: replaySoloEndS - replaySoloStartS,
            layers: [layer(
                track: replayTrack,
                transform: replayTransform,
                transformTimeS: plan.replayStartS
            )]
        )

        let replayEndS = plan.replayStartS + replayDurationS
        if plan.exitTransitionDurationS > 0 {
            let range = CMTimeRange(
                start: CMTime(seconds: plan.cameraOutroStartS, preferredTimescale: 600),
                duration: CMTime(seconds: plan.exitTransitionDurationS, preferredTimescale: 600)
            )
            let replayTransitionLayer = layer(
                track: replayTrack,
                transform: replayTransform,
                transformTimeS: plan.replayStartS
            )
            let outroTransitionLayer = layer(
                track: cameraOutroTrack,
                transform: cameraTransform,
                transformTimeS: plan.cameraOutroStartS
            )
            replayTransitionLayer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: range)
            outroTransitionLayer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: range)
            addInstruction(
                startS: plan.cameraOutroStartS,
                durationS: plan.exitTransitionDurationS,
                layers: [outroTransitionLayer, replayTransitionLayer]
            )
        }
        addInstruction(
            startS: replayEndS,
            durationS: plan.outputDurationS - replayEndS,
            layers: [layer(
                track: cameraOutroTrack,
                transform: cameraTransform,
                transformTimeS: plan.cameraOutroStartS
            )]
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        videoComposition.instructions = instructions

        try await exportComposition(
            composition,
            videoComposition: videoComposition,
            outputURL: outputURL,
            stage: "story-composition"
        )

        return CameraRunVideoCompositionArtifact(
            url: outputURL,
            durationS: plan.outputDurationS,
            canvas: canvas,
            sourceCount: cameraArtifact.sourceCount
        )
    }

    /// Applies a three-part 1x → slow motion → 1x timing edit to an already
    /// rendered Camera Run. Scaling the finished composition keeps the camera
    /// texture, measured 3D, native field, watermark and microphone perfectly
    /// synchronized without mutating any source artifact.
    func applySpeedRamp(
        to artifact: CameraRunVideoCompositionArtifact,
        sourceRange: CameraRunTrim,
        playbackRate: Double,
        outputURL: URL
    ) async throws -> CameraRunVideoCompositionArtifact {
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CameraRunVideoCompositionError.outputExists
        }
        let asset = AVURLAsset(url: artifact.url)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw CameraRunVideoCompositionError.missingVideoTrack("speed-ramp source")
        }
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
        let sourceVideoRange = try await sourceVideo.load(.timeRange)
        let plan = try CameraRunSpeedRampPlan.make(
            sourceDurationS: sourceVideoRange.duration.seconds,
            sourceRange: sourceRange,
            playbackRate: playbackRate
        )
        let composition = AVMutableComposition()
        guard let outputVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CameraRunVideoCompositionError.cannotAddTrack
        }

        do {
            outputVideo.preferredTransform = try await sourceVideo.load(.preferredTransform)
            let beforeDuration = CMTime(
                seconds: plan.sourceRange.startS,
                preferredTimescale: 600
            )
            let slowSourceDuration = CMTime(
                seconds: plan.sourceRange.durationS,
                preferredTimescale: 600
            )
            let slowOutputDuration = CMTime(
                seconds: plan.sourceRange.durationS / plan.playbackRate,
                preferredTimescale: 600
            )
            let beforeSourceRange = CMTimeRange(
                start: sourceVideoRange.start,
                duration: beforeDuration
            )
            let slowSourceRange = CMTimeRange(
                start: sourceVideoRange.start + beforeDuration,
                duration: slowSourceDuration
            )
            let afterSourceRange = CMTimeRange(
                start: CMTimeRangeGetEnd(slowSourceRange),
                end: CMTimeRangeGetEnd(sourceVideoRange)
            )

            if beforeSourceRange.duration > .zero {
                try outputVideo.insertTimeRange(beforeSourceRange, of: sourceVideo, at: .zero)
            }
            try outputVideo.insertTimeRange(slowSourceRange, of: sourceVideo, at: beforeDuration)
            outputVideo.scaleTimeRange(
                CMTimeRange(start: beforeDuration, duration: slowSourceDuration),
                toDuration: slowOutputDuration
            )
            let afterOutputStart = beforeDuration + slowOutputDuration
            if afterSourceRange.duration > .zero {
                try outputVideo.insertTimeRange(afterSourceRange, of: sourceVideo, at: afterOutputStart)
            }

            if let sourceAudio,
               let outputAudio = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let audioRange = try await sourceAudio.load(.timeRange)

                func insertAudio(_ sourceRange: CMTimeRange, at outputStart: CMTime) throws {
                    let sharedRange = CMTimeRangeGetIntersection(sourceRange, otherRange: audioRange)
                    guard sharedRange.duration > .zero else { return }
                    try outputAudio.insertTimeRange(
                        sharedRange,
                        of: sourceAudio,
                        at: outputStart + sharedRange.start - sourceRange.start
                    )
                }

                try insertAudio(beforeSourceRange, at: .zero)
                // Deliberately leave the slowed throw silent: voices before
                // and after stay natural and the reaction remains in sync.
                // A designed trick SFX can occupy this gap later without
                // time-stretching AAC microphone samples.
                try insertAudio(afterSourceRange, at: afterOutputStart)
            }
        } catch {
            throw CameraRunVideoCompositionError.exportFailed(error.localizedDescription)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Force a frame-based video composition for the variable-rate timing
        // map. Without it, AVAssetExportSession attempts to preserve the
        // source sample tables and rejects the fractional edit on iPhone.
        let videoComposition = try await AVVideoComposition.videoComposition(
            withPropertiesOf: composition
        )
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CameraRunVideoCompositionError.cannotCreateExporter
        }
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true
        do {
            try await exporter.export(to: outputURL, as: .mp4)
        } catch {
            throw CameraRunVideoCompositionError.exportFailed(
                "[speed-ramp] \(Self.exportDiagnostic(error: error))"
            )
        }
        return CameraRunVideoCompositionArtifact(
            url: outputURL,
            durationS: plan.outputDurationS,
            canvas: artifact.canvas,
            sourceCount: artifact.sourceCount
        )
    }

    /// AVFoundation occasionally tears down a valid export while another
    /// RealityKit/AV playback surface is releasing its media resources. The
    /// physical-device symptom is the otherwise opaque "Operation Stopped".
    /// Use a fresh exporter for one bounded retry and include the exact stage,
    /// domain, code and exporter state if it still fails. A cancelled parent
    /// task is never retried.
    private func exportComposition(
        _ asset: AVAsset,
        videoComposition: AVVideoComposition,
        outputURL: URL,
        stage: String
    ) async throws {
        let maximumAttempts = 2
        var lastFailure = "unknown export failure"

        for attempt in 1 ... maximumAttempts {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }

            guard let exporter = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                throw CameraRunVideoCompositionError.cannotCreateExporter
            }
            exporter.videoComposition = videoComposition
            exporter.shouldOptimizeForNetworkUse = true

            do {
                try await exporter.export(to: outputURL, as: .mp4)
                return
            } catch {
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: outputURL)
                    throw CameraRunVideoCompositionError.exportCancelled
                }
                lastFailure = Self.exportDiagnostic(error: error)
                try? FileManager.default.removeItem(at: outputURL)
                guard attempt < maximumAttempts else { break }

                // Let VideoToolbox/Metal release the previous session before
                // constructing a fresh AVAssetExportSession.
                try await Task.sleep(for: .milliseconds(300))
            }
        }

        throw CameraRunVideoCompositionError.exportFailed(
            "[\(stage)] \(lastFailure) · retried once"
        )
    }

    private static func exportDiagnostic(error: Error) -> String {
        let nsError = error as NSError
        let primary = "\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
        guard let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return primary
        }
        return "\(primary) · underlying \(underlying.domain)(\(underlying.code)): \(underlying.localizedDescription)"
    }

    private func load(_ sources: [CameraRunVideoSource]) async throws -> [LoadedSource] {
        var loaded: [LoadedSource] = []
        for source in sources {
            let asset = AVURLAsset(url: source.url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                throw CameraRunVideoCompositionError.missingVideoTrack(source.position.rawValue)
            }
            async let duration = asset.load(.duration)
            async let audioTracks = asset.loadTracks(withMediaType: .audio)
            async let naturalSize = track.load(.naturalSize)
            async let preferredTransform = track.load(.preferredTransform)
            loaded.append(try await LoadedSource(
                source: source,
                asset: asset,
                track: track,
                audioTrack: audioTracks.first,
                duration: duration,
                naturalSize: naturalSize,
                preferredTransform: preferredTransform
            ))
        }
        return loaded
    }

    nonisolated static func aspectFillTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        destination: CGRect
    ) -> CGAffineTransform {
        let sourceRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(width: abs(sourceRect.width), height: abs(sourceRect.height))
        guard orientedSize.width > 0, orientedSize.height > 0,
              destination.width > 0, destination.height > 0 else { return preferredTransform }

        let scale = max(destination.width / orientedSize.width, destination.height / orientedSize.height)
        let renderedSize = CGSize(width: orientedSize.width * scale, height: orientedSize.height * scale)
        let offsetX = destination.minX + (destination.width - renderedSize.width) / 2
        let offsetY = destination.minY + (destination.height - renderedSize.height) / 2

        return preferredTransform
            .concatenating(CGAffineTransform(translationX: -sourceRect.minX, y: -sourceRect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
    }

    private func burnCaptions(
        inputURL: URL,
        outputURL: URL,
        captions: [CameraRunCaption],
        trim: CameraRunTrim,
        canvas: CGSize,
        frameRate: Int
    ) async throws {
        let silentOutputURL = outputURL.deletingLastPathComponent().appending(
            path: ".caption-video-\(UUID().uuidString).mp4"
        )
        defer { try? FileManager.default.removeItem(at: silentOutputURL) }
        let asset = AVURLAsset(url: inputURL)
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw CameraRunVideoCompositionError.missingVideoTrack("rendered camera")
        }
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: sourceTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw CameraRunVideoCompositionError.exportFailed("Caption reader could not add its video output.")
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: silentOutputURL, fileType: .mp4)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(canvas.width),
                AVVideoHeightKey: Int(canvas.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(canvas.width),
                kCVPixelBufferHeightKey as String: Int(canvas.height)
            ]
        )
        guard writer.canAdd(writerInput) else {
            throw CameraRunVideoCompositionError.cannotAddTrack
        }
        writer.add(writerInput)
        guard writer.startWriting(), reader.startReading() else {
            throw CameraRunVideoCompositionError.exportFailed(
                writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "Caption pass could not start."
            )
        }
        writer.startSession(atSourceTime: .zero)

        let context = CIContext(options: [.cacheIntermediates: false])
        let overlays = Dictionary(uniqueKeysWithValues: captions.compactMap { caption in
            Self.captionOverlay(for: caption, canvas: canvas).map { (caption.id, $0) }
        })

        while let sample = readerOutput.copyNextSampleBuffer() {
            try Task.checkCancellation()
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample),
                  let pool = adaptor.pixelBufferPool else {
                throw CameraRunVideoCompositionError.exportFailed("Caption pass received no video frame.")
            }
            var destinationBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destinationBuffer) == kCVReturnSuccess,
                  let destinationBuffer else {
                throw CameraRunVideoCompositionError.exportFailed("Caption pass could not allocate a video frame.")
            }

            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let originalTimeS = trim.startS + CMTimeGetSeconds(pts)
            var frameImage = CIImage(cvPixelBuffer: sourceBuffer)
            for caption in captions where caption.isVisible(atOriginalTimeS: originalTimeS) {
                if let overlay = overlays[caption.id] {
                    frameImage = overlay.composited(over: frameImage)
                }
            }
            context.render(
                frameImage,
                to: destinationBuffer,
                bounds: CGRect(origin: .zero, size: canvas),
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            guard adaptor.append(destinationBuffer, withPresentationTime: pts) else {
                throw CameraRunVideoCompositionError.exportFailed(
                    writer.error?.localizedDescription ?? "Caption frame append failed."
                )
            }
        }

        guard reader.status == .completed else {
            writer.cancelWriting()
            throw CameraRunVideoCompositionError.exportFailed(
                reader.error?.localizedDescription ?? "Caption reader did not complete."
            )
        }
        writerInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw CameraRunVideoCompositionError.exportFailed(
                writer.error?.localizedDescription ?? "Caption writer did not complete."
            )
        }
        _ = try await attachAudio(
            videoURL: silentOutputURL,
            audioSourceURL: inputURL,
            audioStartS: 0,
            outputURL: outputURL,
            canvas: canvas
        )
        _ = frameRate // Output cadence follows the already-rendered source PTS.
    }

    private static func captionOverlay(
        for caption: CameraRunCaption,
        canvas: CGSize
    ) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: canvas.width * 0.06, weight: .black),
                .foregroundColor: UIColor.white,
                .paragraphStyle: style,
                .strokeColor: UIColor.black.withAlphaComponent(0.8),
                .strokeWidth: -4
            ]
            let y: CGFloat
            switch caption.placement {
            case .top: y = canvas.height * 0.10
            case .center: y = canvas.height * 0.44
            case .bottom: y = canvas.height * 0.80
            }
            NSString(string: caption.text).draw(
                in: CGRect(x: canvas.width * 0.06, y: y, width: canvas.width * 0.88, height: canvas.height * 0.12),
                withAttributes: attributes
            )
        }
        return CIImage(image: image)
    }

}
