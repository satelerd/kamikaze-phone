import CoreGraphics
import CoreVideo
import Foundation
import KamikazeMotionCore
import RealityKit
import UIKit
@preconcurrency import AVFoundation

nonisolated public struct ReplayVideoCanvas: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int = 1_080, height: Int = 1_920) {
        self.width = width
        self.height = height
    }

    public static let vertical = ReplayVideoCanvas()
}

nonisolated public enum ReplayVideoExportError: Error, Equatable, LocalizedError, Sendable {
    case emptyReplay
    case invalidCanvas
    case invalidFrameRate
    case invalidTrim
    case outputExists
    case cannotCreateWriter(String)
    case writerFailed(String)
    case renderFailed(String)
    case pixelBufferFailed
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .emptyReplay: "The replay contains no measured frames."
        case .invalidCanvas: "The export canvas must have positive dimensions."
        case .invalidFrameRate: "The export frame rate must be between 1 and 60 FPS."
        case .invalidTrim: "The requested trim does not overlap the replay."
        case .outputExists: "The requested export output already exists."
        case let .cannotCreateWriter(reason): "Could not create the video writer: \(reason)"
        case let .writerFailed(reason): "The video writer failed: \(reason)"
        case let .renderFailed(reason): "The replay frame could not be rendered: \(reason)"
        case .pixelBufferFailed: "The rendered frame could not be converted to a video frame."
        case .cancelled: "Replay export was cancelled."
        }
    }
}

nonisolated public struct ReplayVideoExportPlan: Codable, Equatable, Sendable {
    public let sourceDurationMs: Double
    public let trim: CameraRunTrim
    public let canvas: ReplayVideoCanvas
    public let frameRate: Int
    public let frameCount: Int
    /// Source replay timestamps, in milliseconds.  The output writer maps
    /// frame index to a zero-based video PTS while this list preserves the
    /// measured source time used for rendering.
    public let sourceFrameTimesMs: [Double]

    public var durationS: Double { trim.durationS }

    public init(
        frames: [ReplayFrame],
        trim: CameraRunTrim,
        canvas: ReplayVideoCanvas = .vertical,
        frameRate: Int = 30
    ) throws {
        guard !frames.isEmpty else { throw ReplayVideoExportError.emptyReplay }
        guard canvas.width > 0, canvas.height > 0 else {
            throw ReplayVideoExportError.invalidCanvas
        }
        guard (1...60).contains(frameRate) else {
            throw ReplayVideoExportError.invalidFrameRate
        }
        let sourceDurationMs = max(0, frames.last?.timestampMs ?? 0)
        let boundedTrim = trim.clamped(to: sourceDurationMs / 1_000)
        guard boundedTrim.durationS > 0 else { throw ReplayVideoExportError.invalidTrim }

        // Binary floating point can represent an exact authored window such
        // as 0.8 - 0.2 as 0.6000000000000001. A raw ceil would then invent a
        // seventh frame at 10 FPS. Remove only machine-scale noise before
        // rounding up; genuinely partial frame intervals still get a frame.
        let cadenceCount = boundedTrim.durationS * Double(frameRate)
        let frameCount = max(1, Int(ceil(cadenceCount - 1e-9)))
        let sourceFrameTimesMs = (0..<frameCount).map { index in
            let relativeS = min(
                boundedTrim.durationS,
                Double(index) / Double(frameRate)
            )
            let sourceMs = (boundedTrim.startS + relativeS) * 1_000
            return (sourceMs * 1_000_000).rounded() / 1_000_000
        }
        self.sourceDurationMs = sourceDurationMs
        self.trim = boundedTrim
        self.canvas = canvas
        self.frameRate = frameRate
        self.frameCount = frameCount
        self.sourceFrameTimesMs = sourceFrameTimesMs
    }
}

nonisolated public struct ReplayVideoExportRequest: Sendable {
    public let frames: [ReplayFrame]
    public let edit: CameraRunEdit
    public let canvas: ReplayVideoCanvas
    public let frameRate: Int
    public let outputURL: URL

    public init(
        frames: [ReplayFrame],
        edit: CameraRunEdit,
        outputURL: URL,
        canvas: ReplayVideoCanvas = .vertical,
        frameRate: Int = 30
    ) {
        self.frames = ReplayBuilder.normalized(frames)
        self.edit = edit
        self.canvas = canvas
        self.frameRate = frameRate
        self.outputURL = outputURL
    }

    public init(
        capture: MotionCaptureV3,
        edit: CameraRunEdit? = nil,
        outputURL: URL,
        canvas: ReplayVideoCanvas = .vertical,
        frameRate: Int = 30
    ) {
        let frames = ReplayBuilder.normalized(ReplayBuilder.buildFrames(
            payload: capture.samplePayload,
            boundaries: capture.attempt.boundaries
        ))
        self.init(
            frames: frames,
            edit: edit ?? CameraRunEdit(
                trim: CameraRunTrim(
                    startS: 0,
                    endS: (frames.last?.timestampMs ?? 0) / 1_000
                )
            ),
            outputURL: outputURL,
            canvas: canvas,
            frameRate: frameRate
        )
    }

    public func plan() throws -> ReplayVideoExportPlan {
        try ReplayVideoExportPlan(
            frames: frames,
            trim: edit.trim,
            canvas: canvas,
            frameRate: frameRate
        )
    }
}

/// Rendering is injected so the production path can later use an offscreen
/// RealityKit renderer, while tests and the simulator have a deterministic
/// Core Graphics renderer.  Every rendered pose comes from a real
/// `ReplayFrame`; the exporter has no synthetic motion generator.
@MainActor
public protocol ReplayVideoFrameRenderer {
    func image(
        for frame: ReplayFrame,
        canvas: ReplayVideoCanvas,
        caption: CameraRunCaption?
    ) async throws -> CGImage
}

/// A lightweight vertical renderer for the prototype.  It draws the measured
/// orientation and measured telemetry into a phone-shaped card.  The visual
/// shell is intentionally replaceable; the source frame/time contract is the
/// part that must remain stable when a RealityKit renderer is integrated.
@MainActor
public struct CoreGraphicsReplayFrameRenderer: ReplayVideoFrameRenderer {
    public init() {}

    public func image(
        for frame: ReplayFrame,
        canvas: ReplayVideoCanvas,
        caption: CameraRunCaption?
    ) async throws -> CGImage {
        guard canvas.width > 0, canvas.height > 0 else {
            throw ReplayVideoExportError.invalidCanvas
        }
        let size = CGSize(width: canvas.width, height: canvas.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            let width = size.width
            let height = size.height

            // Dark vertical stage; the values below are visual treatment only.
            context.setFillColor(UIColor(red: 0.025, green: 0.03, blue: 0.045, alpha: 1).cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(UIColor(red: 0.10, green: 0.13, blue: 0.18, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: width * 0.08, y: height * 0.21, width: width * 0.84, height: height * 0.42))

            context.saveGState()
            context.translateBy(x: width / 2, y: height * 0.49)
            context.rotate(by: CGFloat(Self.rotationAngle(from: frame.quaternion)))
            let phoneRect = CGRect(
                x: -width * 0.27,
                y: -height * 0.18,
                width: width * 0.54,
                height: height * 0.36
            )
            let phonePath = UIBezierPath(roundedRect: phoneRect, cornerRadius: width * 0.045)
            UIColor(red: 0.68, green: 0.73, blue: 0.80, alpha: 1).setFill()
            phonePath.fill()
            UIColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1).setStroke()
            phonePath.lineWidth = width * 0.012
            phonePath.stroke()

            let screenRect = phoneRect.insetBy(dx: width * 0.025, dy: height * 0.015)
            let screenPath = UIBezierPath(roundedRect: screenRect, cornerRadius: width * 0.032)
            UIColor(red: 0.015, green: 0.02, blue: 0.03, alpha: 1).setFill()
            screenPath.fill()
            context.restoreGState()

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: width * 0.035, weight: .black),
                .foregroundColor: UIColor.white
            ]
            NSString(string: "KAMIKAZE REPLAY").draw(
                at: CGPoint(x: width * 0.08, y: height * 0.07),
                withAttributes: titleAttributes
            )

            let telemetry = String(format: "%.0f MS   GYRO %.0f°/S", frame.timestampMs, frame.gyroDps)
            let telemetryAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: width * 0.027, weight: .medium),
                .foregroundColor: UIColor(red: 0.63, green: 1, blue: 0.28, alpha: 1)
            ]
            NSString(string: telemetry).draw(
                at: CGPoint(x: width * 0.08, y: height * 0.88),
                withAttributes: telemetryAttributes
            )

            if let caption, !caption.text.isEmpty {
                let captionAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: width * 0.052, weight: .black),
                    .foregroundColor: UIColor.white
                ]
                let captionSize = NSString(string: caption.text).size(withAttributes: captionAttributes)
                let y: CGFloat
                switch caption.placement {
                case .top: y = height * 0.13
                case .center: y = height * 0.54
                case .bottom: y = height * 0.78
                }
                NSString(string: caption.text).draw(
                    at: CGPoint(x: max(width * 0.06, (width - captionSize.width) / 2), y: y),
                    withAttributes: captionAttributes
                )
            }
        }
        // UIGraphicsImageRenderer should always return a CGImage, but retain
        // an explicit error instead of producing a blank artifact.
        guard let image = rendered.cgImage else {
            throw ReplayVideoExportError.renderFailed("Renderer returned no image.")
        }
        return image
    }

    private static func rotationAngle(from quaternion: Quaternion) -> Double {
        let sinZ = 2 * (quaternion.w * quaternion.z + quaternion.x * quaternion.y)
        let cosZ = 1 - 2 * (quaternion.y * quaternion.y + quaternion.z * quaternion.z)
        return atan2(sinZ, cosZ)
    }
}

/// Real 3D renderer for exported replays. It uses the same authored phone,
/// materials and light rig as live/replay RealityViews, then snapshots a
/// non-AR RealityKit scene at each measured quaternion. The renderer owns one
/// scene for the complete export; it never rebuilds the model per frame.
@MainActor
final class RealityKitReplayFrameRenderer: ReplayVideoFrameRenderer {
    private let appearance: PhoneAppearance
    private let accent: UIColor
    private var arView: ARView?
    private var phone: Entity?
    private var activeCanvas: ReplayVideoCanvas?
    private let screenVideoGenerator: AVAssetImageGenerator?
    private let screenVideoOffsetS: Double

    init(
        appearance: PhoneAppearance,
        accent: UIColor,
        screenVideoURL: URL? = nil,
        screenVideoOffsetS: Double = 0
    ) {
        self.appearance = appearance
        self.accent = accent
        self.screenVideoOffsetS = max(0, screenVideoOffsetS)
        if let screenVideoURL {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: screenVideoURL))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            screenVideoGenerator = generator
        } else {
            screenVideoGenerator = nil
        }
    }

    func image(
        for frame: ReplayFrame,
        canvas: ReplayVideoCanvas,
        caption: CameraRunCaption?
    ) async throws -> CGImage {
        try prepareScene(for: canvas)
        guard let arView, let phone else {
            throw ReplayVideoExportError.renderFailed("RealityKit scene was not created.")
        }
        phone.orientation = simd_quatf(
            ix: Float(frame.quaternion.x),
            iy: Float(frame.quaternion.y),
            iz: Float(frame.quaternion.z),
            r: Float(frame.quaternion.w)
        )
        await applyScreenVideoFrame(atReplayTimeMs: frame.timestampMs, to: phone)

        let snapshot: UIImage = try await withCheckedThrowingContinuation { continuation in
            arView.snapshot(saveToHDR: false) { image in
                guard let image else {
                    continuation.resume(throwing: ReplayVideoExportError.renderFailed(
                        "RealityKit returned no snapshot."
                    ))
                    return
                }
                continuation.resume(returning: image)
            }
        }
        return try Self.drawExportFrame(
            snapshot: snapshot,
            frame: frame,
            canvas: canvas,
            caption: caption
        )
    }

    private func applyScreenVideoFrame(atReplayTimeMs replayTimeMs: Double, to phone: Entity) async {
        guard let screenVideoGenerator else { return }
        let sourceS = screenVideoOffsetS + max(0, replayTimeMs / 1_000)
        guard let (image, _) = try? await screenVideoGenerator.image(
            at: CMTime(seconds: sourceS, preferredTimescale: 600)
        ) else { return }
        guard let texture = try? await TextureResource(
            image: image,
            options: .init(semantic: .color)
        ) else { return }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        PhoneModelFactory.applyScreenMaterial(to: phone, material: material)
    }

    private func prepareScene(for canvas: ReplayVideoCanvas) throws {
        guard canvas.width > 0, canvas.height > 0 else {
            throw ReplayVideoExportError.invalidCanvas
        }
        guard arView == nil || activeCanvas != canvas else { return }

        let size = CGSize(width: canvas.width, height: canvas.height)
        let view = ARView(
            frame: CGRect(origin: .zero, size: size),
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        view.contentScaleFactor = 1
        view.environment.background = .color(UIColor(red: 0.02, green: 0.025, blue: 0.04, alpha: 1))

        let anchor = AnchorEntity(world: .zero)
        let phone = PhoneModelFactory.makePhone(appearance: appearance, accent: accent)
        phone.name = "export-phone"
        // ARView's non-AR camera sits at the origin and looks down -Z. Keep
        // the phone's pivot intact and move only its world position.
        phone.position.z = -0.49
        anchor.addChild(phone)
        anchor.addChild(PhoneModelFactory.makeLightRig())
        view.scene.addAnchor(anchor)

        arView = view
        self.phone = phone
        activeCanvas = canvas
    }

    private static func drawExportFrame(
        snapshot: UIImage,
        frame: ReplayFrame,
        canvas: ReplayVideoCanvas,
        caption: CameraRunCaption?
    ) throws -> CGImage {
        let size = CGSize(width: canvas.width, height: canvas.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            snapshot.draw(in: CGRect(origin: .zero, size: size))

            let title: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: size.width * 0.033, weight: .black),
                .foregroundColor: UIColor.white
            ]
            NSString(string: "KAMIKAZE · MEASURED REPLAY").draw(
                at: CGPoint(x: size.width * 0.06, y: size.height * 0.055),
                withAttributes: title
            )
            let telemetry: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: size.width * 0.026, weight: .bold),
                .foregroundColor: UIColor(red: 0.84, green: 1, blue: 0.29, alpha: 1)
            ]
            NSString(string: String(format: "%.0f MS  ·  %.0f°/S", frame.timestampMs, frame.gyroDps)).draw(
                at: CGPoint(x: size.width * 0.06, y: size.height * 0.91),
                withAttributes: telemetry
            )

            if let caption, !caption.text.isEmpty {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: size.width * 0.055, weight: .black),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: style,
                    .strokeColor: UIColor.black,
                    .strokeWidth: -3
                ]
                let y: CGFloat
                switch caption.placement {
                case .top: y = size.height * 0.12
                case .center: y = size.height * 0.48
                case .bottom: y = size.height * 0.80
                }
                NSString(string: caption.text).draw(
                    in: CGRect(x: size.width * 0.06, y: y, width: size.width * 0.88, height: size.height * 0.12),
                    withAttributes: attributes
                )
            }
        }
        guard let cgImage = image.cgImage else {
            throw ReplayVideoExportError.renderFailed("RealityKit snapshot could not be rasterized.")
        }
        return cgImage
    }
}

nonisolated public struct ReplayVideoArtifact: Codable, Equatable, Sendable {
    public let url: URL
    public let durationS: Double
    public let frameCount: Int
    public let canvas: ReplayVideoCanvas

    public var shareURL: URL { url }

    public init(url: URL, durationS: Double, frameCount: Int, canvas: ReplayVideoCanvas) {
        self.url = url
        self.durationS = durationS
        self.frameCount = frameCount
        self.canvas = canvas
    }
}

nonisolated private final class ReplayVideoWriterBox: @unchecked Sendable {
    let value: AVAssetWriter

    init(_ value: AVAssetWriter) {
        self.value = value
    }
}

/// AVAssetWriter implementation for ordinary measured replay export.  It is
/// main-actor isolated because renderers and UIKit/Core Graphics are main
/// actor objects in this prototype.  A future integration can move the
/// renderer to a dedicated queue without changing the plan or artifact API.
@MainActor
public final class ReplayVideoExporter {
    public init() {}

    public func export(
        _ request: ReplayVideoExportRequest,
        renderer: any ReplayVideoFrameRenderer = CoreGraphicsReplayFrameRenderer()
    ) async throws -> ReplayVideoArtifact {
        let plan = try request.plan()
        guard !FileManager.default.fileExists(atPath: request.outputURL.path) else {
            throw ReplayVideoExportError.outputExists
        }
        do {
            try FileManager.default.createDirectory(
                at: request.outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw ReplayVideoExportError.cannotCreateWriter(error.localizedDescription)
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: request.outputURL, fileType: .mp4)
        } catch {
            throw ReplayVideoExportError.cannotCreateWriter(error.localizedDescription)
        }
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: plan.canvas.width,
                AVVideoHeightKey: plan.canvas.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: plan.canvas.width,
                kCVPixelBufferHeightKey as String: plan.canvas.height
            ]
        )
        guard writer.canAdd(input) else {
            throw ReplayVideoExportError.cannotCreateWriter("Writer cannot add video input.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw ReplayVideoExportError.cannotCreateWriter(
                writer.error?.localizedDescription ?? "startWriting returned false"
            )
        }
        writer.startSession(atSourceTime: .zero)

        do {
            for sourceTimeMs in plan.sourceFrameTimesMs {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(2))
                }
                let sourceFrame = ReplayBuilder.sample(request.frames, at: sourceTimeMs)
                let relativeSourceTimeS = max(0, sourceTimeMs / 1_000 - plan.trim.startS)
                let caption = request.edit.captions.first {
                    $0.isVisible(atOriginalTimeS: sourceTimeMs / 1_000)
                }
                let image: CGImage
                do {
                    image = try await renderer.image(
                        for: sourceFrame,
                        canvas: plan.canvas,
                        caption: caption
                    )
                } catch let error as ReplayVideoExportError {
                    throw error
                } catch {
                    throw ReplayVideoExportError.renderFailed(error.localizedDescription)
                }
                guard let pixelBuffer = Self.makePixelBuffer(
                    from: image,
                    width: plan.canvas.width,
                    height: plan.canvas.height
                ) else {
                    throw ReplayVideoExportError.pixelBufferFailed
                }
                let presentationTime = CMTime(
                    seconds: relativeSourceTimeS,
                    preferredTimescale: 600
                )
                guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    throw ReplayVideoExportError.writerFailed(
                        writer.error?.localizedDescription ?? "append returned false"
                    )
                }
            }
            input.markAsFinished()
            try await Self.finish(writer)
        } catch is CancellationError {
            writer.cancelWriting()
            throw ReplayVideoExportError.cancelled
        } catch let error as ReplayVideoExportError {
            writer.cancelWriting()
            throw error
        } catch {
            writer.cancelWriting()
            throw ReplayVideoExportError.writerFailed(error.localizedDescription)
        }

        return ReplayVideoArtifact(
            url: request.outputURL,
            durationS: plan.durationS,
            frameCount: plan.frameCount,
            canvas: plan.canvas
        )
    }

    private static func finish(_ writer: AVAssetWriter) async throws {
        let writerBox = ReplayVideoWriterBox(writer)
        try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting {
                if writerBox.value.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ReplayVideoExportError.writerFailed(
                        writerBox.value.error?.localizedDescription ?? "finishWriting failed"
                    ))
                }
            }
        }
    }

    private static func makePixelBuffer(
        from image: CGImage,
        width: Int,
        height: Int
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess,
        let pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}
