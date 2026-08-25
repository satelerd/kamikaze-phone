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

@MainActor
public final class CameraRunVideoComposer {
    private struct LoadedSource {
        let source: CameraRunVideoSource
        let asset: AVURLAsset
        let track: AVAssetTrack
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

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CameraRunVideoCompositionError.cannotCreateExporter
        }
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true
        do {
            try await exporter.export(to: baseOutputURL, as: .mp4)
        } catch is CancellationError {
            throw CameraRunVideoCompositionError.exportCancelled
        } catch {
            throw CameraRunVideoCompositionError.exportFailed(error.localizedDescription)
        }

        if !visibleCaptions.isEmpty {
            do {
                try await Self.burnCaptions(
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
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: artifact.url)
            }
        } catch {
            throw CameraRunVideoCompositionError.photosSaveFailed(error.localizedDescription)
        }
    }

    /// Adds the measured RealityKit replay as an end card after the edited
    /// camera footage. Keeping it sequential in this beta preserves the full
    /// pre-talk/throw/post-talk cut while giving the replay its entire canvas;
    /// a later editor can expose overlay timing without changing either source.
    public func appendReplay(
        cameraArtifact: CameraRunVideoCompositionArtifact,
        replayArtifact: ReplayVideoArtifact,
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
        guard cameraDurationS > 0, replayDurationS > 0 else {
            throw CameraRunVideoCompositionError.invalidDuration
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let composition = AVMutableComposition()
        guard let cameraTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let replayTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CameraRunVideoCompositionError.cannotAddTrack
        }

        do {
            try cameraTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: camera.duration),
                of: camera.track,
                at: .zero
            )
            try replayTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: replay.duration),
                of: replay.track,
                at: camera.duration
            )
        } catch {
            throw CameraRunVideoCompositionError.exportFailed(error.localizedDescription)
        }

        let destination = CGRect(origin: .zero, size: canvas)
        let cameraLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: cameraTrack)
        cameraLayer.setTransform(Self.aspectFillTransform(
            naturalSize: camera.naturalSize,
            preferredTransform: camera.preferredTransform,
            destination: destination
        ), at: .zero)
        let replayLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: replayTrack)
        replayLayer.setTransform(Self.aspectFillTransform(
            naturalSize: replay.naturalSize,
            preferredTransform: replay.preferredTransform,
            destination: destination
        ), at: camera.duration)

        let cameraInstruction = AVMutableVideoCompositionInstruction()
        cameraInstruction.timeRange = CMTimeRange(start: .zero, duration: camera.duration)
        cameraInstruction.layerInstructions = [cameraLayer]
        let replayInstruction = AVMutableVideoCompositionInstruction()
        replayInstruction.timeRange = CMTimeRange(start: camera.duration, duration: replay.duration)
        replayInstruction.layerInstructions = [replayLayer]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        videoComposition.instructions = [cameraInstruction, replayInstruction]

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
        } catch is CancellationError {
            throw CameraRunVideoCompositionError.exportCancelled
        } catch {
            throw CameraRunVideoCompositionError.exportFailed(error.localizedDescription)
        }

        return CameraRunVideoCompositionArtifact(
            url: outputURL,
            durationS: cameraDurationS + replayDurationS,
            canvas: canvas,
            sourceCount: cameraArtifact.sourceCount
        )
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
            async let naturalSize = track.load(.naturalSize)
            async let preferredTransform = track.load(.preferredTransform)
            loaded.append(try await LoadedSource(
                source: source,
                asset: asset,
                track: track,
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

    private static func burnCaptions(
        inputURL: URL,
        outputURL: URL,
        captions: [CameraRunCaption],
        trim: CameraRunTrim,
        canvas: CGSize,
        frameRate: Int
    ) async throws {
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

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
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
            captionOverlay(for: caption, canvas: canvas).map { (caption.id, $0) }
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
