import CoreGraphics
import CoreVideo
import Foundation
import KamikazeMotionCore
import RealityKit
import SwiftUI
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

/// Player-facing identity burned into a shareable replay. All fields are
/// optional except the product mark so an export never invents a detector
/// result or score that was not present on the captured attempt.
nonisolated struct ReplayVideoBranding: Equatable, Sendable {
    let trickName: String?
    let score: Int?

    init(trickName: String? = nil, score: Int? = nil) {
        let cleanedName = trickName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trickName = cleanedName?.isEmpty == false ? cleanedName : nil
        self.score = score.map { min(100, max(0, $0)) }
    }
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
    private let branding: ReplayVideoBranding

    init(
        appearance: PhoneAppearance,
        accent: UIColor,
        screenVideoURL: URL? = nil,
        screenVideoOffsetS: Double = 0,
        branding: ReplayVideoBranding = .init()
    ) {
        self.appearance = appearance
        self.accent = accent
        self.screenVideoOffsetS = max(0, screenVideoOffsetS)
        self.branding = branding
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
            caption: caption,
            accent: accent,
            branding: branding
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
        // The animated field is composited after RealityKit snapshots the
        // measured phone. Keeping this scene transparent avoids baking the
        // former static black stage into every exported frame.
        view.isOpaque = false
        view.backgroundColor = .clear
        view.environment.background = .color(.clear)

        let anchor = AnchorEntity(world: .zero)
        let phone = PhoneModelFactory.makePhone(appearance: appearance, accent: accent)
        phone.name = "export-phone"
        // ARView's implicit non-AR camera is read-only. Scale the isolated
        // export clone (never the shared model) into a social-video hero
        // framing; the former physical-size render occupied only a few
        // percent of the canvas on device.
        phone.scale *= SIMD3(repeating: canvas.width > canvas.height ? 4.75 : 5.65)
        phone.position.z = canvas.width > canvas.height ? -0.30 : -0.22
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
        caption: CameraRunCaption?,
        accent: UIColor,
        branding: ReplayVideoBranding
    ) throws -> CGImage {
        let size = CGSize(width: canvas.width, height: canvas.height)
        let nativeScene = KamikazeNativeExportScene(
            size: size,
            snapshot: snapshot,
            timeS: frame.timestampMs / 1_000,
            energy: min(1, max(0, frame.gyroDps / 1_100)),
            accent: Color(uiColor: accent),
            branding: branding,
            caption: caption
        )
        let nativeRenderer = ImageRenderer(content: nativeScene)
        nativeRenderer.proposedSize = ProposedViewSize(size)
        nativeRenderer.scale = 1
        nativeRenderer.isOpaque = true
        if let nativeImage = nativeRenderer.cgImage {
            return nativeImage
        }

        // ImageRenderer can decline unsupported platform-backed content. The
        // RealityKit phone is already a UIImage, so this should only be hit on
        // an OS/render-service failure; preserve a deterministic offline path
        // rather than failing a long export at its final frame.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            KamikazeExportArtwork.drawFluxField(
                in: rendererContext.cgContext,
                size: size,
                timeS: frame.timestampMs / 1_000,
                accent: accent
            )
            snapshot.draw(in: CGRect(origin: .zero, size: size))

            KamikazeExportArtwork.drawGlassReceipt(
                in: rendererContext.cgContext,
                size: size,
                branding: branding,
                accent: accent
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

/// The high-fidelity export stage is composed from the exact same SwiftUI
/// primitives as the app: the selected Slipstream/Flux field and iOS 26
/// GlassSurface. RealityKit is rasterized first because ImageRenderer only
/// guarantees SwiftUI-rendered content; placing that image inside this scene
/// lets the native glass refract the real field beneath it.
@MainActor
private struct KamikazeNativeExportScene: View {
    let size: CGSize
    let snapshot: UIImage
    let timeS: Double
    let energy: Double
    let accent: Color
    let branding: ReplayVideoBranding
    let caption: CameraRunCaption?

    var body: some View {
        ZStack {
            SlipstreamField(
                accent: accent,
                energy: energy,
                timeOverride: timeS
            )
            .frame(width: size.width, height: size.height)

            Image(uiImage: snapshot)
                .resizable()
                .frame(width: size.width, height: size.height)

            VStack(spacing: 0) {
                brandCard
                Spacer(minLength: 0)
                resultCard
            }
            .padding(.horizontal, min(size.width, size.height) * 0.055)
            .padding(.vertical, min(size.width, size.height) * 0.050)

            if let caption, !caption.text.isEmpty {
                captionView(caption)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var brandCard: some View {
        let horizontal = size.width > size.height
        let titleSize = horizontal ? size.width * 0.046 : size.width * 0.068
        return GlassSurface(role: .instrumentHUD, cornerRadius: horizontal ? 38 : 32) {
            (
                Text("KAMIKAZE: ").foregroundColor(KamikazeTheme.frost)
                + Text("PHONE FLIP").foregroundColor(accent)
            )
            .font(.system(size: titleSize, weight: .black, design: .rounded))
            .tracking(-titleSize * 0.050)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, horizontal ? 34 : 25)
            .padding(.vertical, horizontal ? 27 : 25)
        }
        .frame(width: size.width * 0.89)
    }

    private var resultCard: some View {
        let horizontal = size.width > size.height
        let trickSize = horizontal ? size.width * 0.035 : size.width * 0.060
        let scoreSize = horizontal ? size.width * 0.070 : size.width * 0.145
        return GlassSurface(role: .contentPanel, cornerRadius: horizontal ? 42 : 36) {
            HStack(alignment: .center, spacing: horizontal ? 34 : 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LANDED TRICK")
                        .font(.system(size: trickSize * 0.37, weight: .bold, design: .monospaced))
                        .tracking(trickSize * 0.035)
                        .foregroundStyle(accent)
                    Text((branding.trickName ?? "MEASURED REPLAY").uppercased())
                        .font(.system(size: trickSize, weight: .black, design: .rounded))
                        .tracking(-trickSize * 0.035)
                        .foregroundStyle(KamikazeTheme.frost)
                        .lineLimit(1)
                        .minimumScaleFactor(0.50)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let score = branding.score {
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(String(score))
                            .font(.system(size: scoreSize, weight: .black, design: .rounded))
                            .tracking(-scoreSize * 0.075)
                            .foregroundStyle(accent)
                            .monospacedDigit()
                        Text("PTS")
                            .font(.system(size: trickSize * 0.34, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
            }
            .padding(.horizontal, horizontal ? 38 : 30)
            .padding(.vertical, horizontal ? 24 : 27)
        }
        .frame(width: size.width * 0.89)
    }

    @ViewBuilder
    private func captionView(_ caption: CameraRunCaption) -> some View {
        VStack {
            if caption.placement != .top { Spacer() }
            Text(caption.text)
                .font(.system(size: size.width * 0.055, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.70), radius: 5, y: 2)
                .padding(.horizontal, size.width * 0.06)
            if caption.placement != .bottom { Spacer() }
        }
        .padding(.vertical, caption.placement == .center ? size.height * 0.40 : size.height * 0.10)
    }
}

/// Offline counterpart to the live Metal field. Video export cannot capture
/// a SwiftUI material or shader view, so this renderer burns a deterministic
/// animated flux field and a glass-style result receipt into every frame.
/// The timestamp is the measured replay timestamp, making exports repeatable.
@MainActor
enum KamikazeExportArtwork {
    private static let pitch = UIColor(red: 0.018, green: 0.024, blue: 0.047, alpha: 1)
    private static let ion = UIColor(red: 0.30, green: 0.40, blue: 1.00, alpha: 1)
    private static let volt = UIColor(red: 0.84, green: 1.00, blue: 0.29, alpha: 1)

    static func drawFluxField(
        in context: CGContext,
        size: CGSize,
        timeS: Double,
        accent: UIColor
    ) {
        let bounds = CGRect(origin: .zero, size: size)
        context.setFillColor(pitch.cgColor)
        context.fill(bounds)

        // Slow pools give the field depth while the current-lines remain the
        // recognizable signature. Their phase is deliberately restrained so
        // compression sees motion without the background fighting the trick.
        context.saveGState()
        context.setBlendMode(.screen)
        let pools: [(CGPoint, CGFloat, UIColor)] = [
            (
                CGPoint(
                    x: size.width * (0.18 + 0.08 * sin(timeS * 0.21)),
                    y: size.height * (0.22 + 0.05 * cos(timeS * 0.17))
                ),
                max(size.width, size.height) * 0.58,
                ion
            ),
            (
                CGPoint(
                    x: size.width * (0.82 + 0.06 * cos(timeS * 0.16)),
                    y: size.height * (0.72 + 0.06 * sin(timeS * 0.19))
                ),
                max(size.width, size.height) * 0.44,
                accent
            )
        ]
        for (center, radius, color) in pools {
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [color.withAlphaComponent(0.20).cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 1]
            ) else { continue }
            context.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius,
                options: [.drawsAfterEndLocation]
            )
        }

        let shortEdge = min(size.width, size.height)
        let primary = ion.blended(with: accent, amount: 0.18)
        for band in 0..<6 {
            let phase = timeS * (0.22 + Double(band) * 0.018) + Double(band) * 0.91
            let baseY = size.height * (0.08 + CGFloat(band) * 0.17)
            let path = currentPath(
                size: size,
                baseY: baseY,
                amplitude: size.height * (0.040 + CGFloat(band % 3) * 0.012),
                phase: phase
            )
            context.addPath(path)
            context.setStrokeColor(primary.withAlphaComponent(0.10).cgColor)
            context.setLineWidth(shortEdge * 0.070)
            context.setLineCap(.round)
            context.strokePath()

            context.addPath(path)
            context.setStrokeColor(primary.withAlphaComponent(0.24).cgColor)
            context.setLineWidth(shortEdge * 0.030)
            context.strokePath()

            context.addPath(path)
            context.setStrokeColor(primary.withAlphaComponent(0.48).cgColor)
            context.setLineWidth(shortEdge * 0.008)
            context.strokePath()
        }
        context.restoreGState()

        guard let vignette = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.48).cgColor] as CFArray,
            locations: [0.52, 1]
        ) else { return }
        context.drawRadialGradient(
            vignette,
            startCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.46),
            startRadius: 0,
            endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.46),
            endRadius: hypot(size.width, size.height) * 0.64,
            options: [.drawsAfterEndLocation]
        )
    }

    static func drawGlassReceipt(
        in context: CGContext,
        size: CGSize,
        branding: ReplayVideoBranding,
        accent: UIColor
    ) {
        let horizontal = size.width > size.height
        let inset = min(size.width, size.height) * 0.055
        let width = horizontal ? size.width * 0.38 : size.width * 0.60
        let height = horizontal ? size.height * 0.23 : size.height * 0.105
        let rect = CGRect(x: inset, y: inset, width: width, height: height)
        let radius = min(rect.height * 0.30, min(size.width, size.height) * 0.035)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: rect.height * 0.10), blur: rect.height * 0.20, color: UIColor.black.withAlphaComponent(0.42).cgColor)
        UIColor(red: 0.045, green: 0.055, blue: 0.085, alpha: 0.72).setFill()
        path.fill()
        context.restoreGState()

        context.saveGState()
        path.addClip()
        guard let sheen = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor.white.withAlphaComponent(0.20).cgColor,
                ion.withAlphaComponent(0.08).cgColor,
                UIColor.clear.cgColor
            ] as CFArray,
            locations: [0, 0.45, 1]
        ) else {
            context.restoreGState()
            return
        }
        context.drawLinearGradient(
            sheen,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: []
        )
        context.restoreGState()

        context.setStrokeColor(UIColor.white.withAlphaComponent(0.24).cgColor)
        context.setLineWidth(max(1.5, min(size.width, size.height) * 0.002))
        path.stroke()

        let brandFont = UIFont.monospacedSystemFont(ofSize: rect.height * 0.125, weight: .black)
        let brand = "KAMIKAZE  /  PHONE FLIP"
        NSString(string: brand).draw(
            at: CGPoint(x: rect.minX + rect.height * 0.20, y: rect.minY + rect.height * 0.17),
            withAttributes: [
                .font: brandFont,
                .foregroundColor: volt
            ]
        )

        let title = (branding.trickName ?? "MEASURED REPLAY").uppercased()
        let titleScale: CGFloat = title.count > 20 ? 0.17 : (title.count > 14 ? 0.21 : 0.255)
        let titleFont = UIFont.systemFont(ofSize: rect.height * titleScale, weight: .black)
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.lineBreakMode = .byTruncatingTail
        NSString(string: title).draw(
            in: CGRect(
                x: rect.minX + rect.height * 0.20,
                y: rect.minY + rect.height * 0.45,
                width: rect.width * (branding.score == nil ? 0.90 : 0.68),
                height: rect.height * 0.38
            ),
            withAttributes: [
                .font: titleFont,
                .foregroundColor: UIColor.white,
                .paragraphStyle: titleParagraph
            ]
        )

        if let score = branding.score {
            let scoreFont = UIFont.systemFont(ofSize: rect.height * 0.45, weight: .black)
            let scoreText = NSString(string: String(score))
            let scoreSize = scoreText.size(withAttributes: [.font: scoreFont])
            scoreText.draw(
                at: CGPoint(
                    x: rect.maxX - rect.height * 0.20 - scoreSize.width,
                    y: rect.midY - scoreSize.height * 0.47
                ),
                withAttributes: [
                    .font: scoreFont,
                    .foregroundColor: accent
                ]
            )
        }
    }

    private static func currentPath(
        size: CGSize,
        baseY: CGFloat,
        amplitude: CGFloat,
        phase: Double
    ) -> CGPath {
        let path = CGMutablePath()
        let segments = 28
        for index in 0...segments {
            let progress = CGFloat(index) / CGFloat(segments)
            let x = size.width * (progress * 1.16 - 0.08)
            let primaryWave = sin(Double(progress) * 7.2 + phase)
            let secondaryWave = sin(Double(progress) * 15.0 - phase * 0.58) * 0.30
            let y = baseY + amplitude * CGFloat(primaryWave + secondaryWave)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

private extension UIColor {
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        let amount = min(1, max(0, amount))
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return self }
        return UIColor(
            red: r1 + (r2 - r1) * amount,
            green: g1 + (g2 - g1) * amount,
            blue: b1 + (b2 - b1) * amount,
            alpha: a1 + (a2 - a1) * amount
        )
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
        renderer: any ReplayVideoFrameRenderer = CoreGraphicsReplayFrameRenderer(),
        progress: ((Int, Int) -> Void)? = nil
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
            for (frameIndex, sourceTimeMs) in plan.sourceFrameTimesMs.enumerated() {
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
                progress?(frameIndex + 1, plan.frameCount)
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
