import Foundation
import KamikazeMotionCore
import Observation

/// The three authored sections of a Camera Run.  A run is deliberately
/// local-first: these values are just a shared time contract between motion,
/// camera and the eventual editor.
nonisolated public enum CameraRunSegment: String, Codable, CaseIterable, Equatable, Sendable {
    case preTalk
    case throwSegment
    case postTalk
}

/// Marker names are ordered on purpose.  A marker is an event on the shared
/// monotonic clock, not a duration guessed from a video or from detector data.
nonisolated public enum CameraRunMarkerKind: String, Codable, CaseIterable, Equatable, Sendable {
    case preTalkStart
    case preTalkEnd
    case throwStart
    case throwEnd
    case postTalkStart
    case postTalkEnd

    public var segment: CameraRunSegment {
        switch self {
        case .preTalkStart, .preTalkEnd: .preTalk
        case .throwStart, .throwEnd: .throwSegment
        case .postTalkStart, .postTalkEnd: .postTalk
        }
    }
}

nonisolated public enum CameraRunMarkerSource: String, Codable, Equatable, Sendable {
    case userInterface
    case motion
    case frontCamera
    case rearCamera
    case system
}

nonisolated public struct CameraRunTimelineMarker: Codable, Equatable, Sendable {
    public let kind: CameraRunMarkerKind
    /// Seconds from the run's monotonic origin.  This is intentionally not a
    /// wall-clock date and cannot jump when the user changes the clock.
    public let timestampS: Double
    public let source: CameraRunMarkerSource

    public init(
        kind: CameraRunMarkerKind,
        timestampS: Double,
        source: CameraRunMarkerSource
    ) {
        self.kind = kind
        self.timestampS = timestampS
        self.source = source
    }
}

nonisolated public enum CameraRunTimelineError: Error, Equatable, Sendable {
    case invalidOrigin
    case invalidTimestamp
    case timestampBeforeOrigin
    case nonMonotonicTimestamp(previous: Double, next: Double)
    case markerOutOfOrder(expected: CameraRunMarkerKind, received: CameraRunMarkerKind)
    case duplicateMarker(CameraRunMarkerKind)
}

/// A small injectable clock adapter.  `ProcessInfo.systemUptime` and
/// AVFoundation's host-time presentation timestamps use the same monotonic
/// family on iOS, so camera PTS values can be converted without a wall-clock
/// or a fabricated offset.  Tests can pass a fixed origin.
nonisolated public struct CameraRunMonotonicClock: Equatable, Sendable {
    public let originUptimeS: Double

    public init(originUptimeS: Double = ProcessInfo.processInfo.systemUptime) {
        self.originUptimeS = originUptimeS
    }

    public func secondsSinceOrigin(atUptimeS uptimeS: Double) -> Double {
        uptimeS - originUptimeS
    }

    public func now() -> Double {
        secondsSinceOrigin(atUptimeS: ProcessInfo.processInfo.systemUptime)
    }
}

/// Shared timeline for sensor evidence and front/rear video.  The strict
/// marker order catches accidental cross-clock wiring early; missing post-talk
/// markers are valid while a run is still recording, but an editor/export plan
/// can require a complete timeline when it needs one.
nonisolated public struct CameraRunTimeline: Codable, Equatable, Sendable {
    public let originUptimeS: Double
    public private(set) var markers: [CameraRunTimelineMarker]

    public init(originUptimeS: Double = ProcessInfo.processInfo.systemUptime) {
        self.originUptimeS = originUptimeS
        self.markers = []
    }

    public var clock: CameraRunMonotonicClock {
        CameraRunMonotonicClock(originUptimeS: originUptimeS)
    }

    public var isComplete: Bool {
        markers.count == CameraRunMarkerKind.allCases.count
    }

    public var durationS: Double {
        markers.last?.timestampS ?? 0
    }

    public mutating func mark(
        _ kind: CameraRunMarkerKind,
        atUptimeS uptimeS: Double,
        source: CameraRunMarkerSource
    ) throws -> CameraRunTimelineMarker {
        guard originUptimeS.isFinite else { throw CameraRunTimelineError.invalidOrigin }
        guard uptimeS.isFinite else { throw CameraRunTimelineError.invalidTimestamp }
        guard uptimeS >= originUptimeS else { throw CameraRunTimelineError.timestampBeforeOrigin }

        if markers.contains(where: { $0.kind == kind }) {
            throw CameraRunTimelineError.duplicateMarker(kind)
        }

        let expected = CameraRunMarkerKind.allCases[markers.count]
        guard expected == kind else {
            throw CameraRunTimelineError.markerOutOfOrder(expected: expected, received: kind)
        }

        let timestampS = clock.secondsSinceOrigin(atUptimeS: uptimeS)
        if let previous = markers.last?.timestampS, timestampS < previous {
            throw CameraRunTimelineError.nonMonotonicTimestamp(previous: previous, next: timestampS)
        }

        let marker = CameraRunTimelineMarker(kind: kind, timestampS: timestampS, source: source)
        markers.append(marker)
        return marker
    }

    public func marker(for kind: CameraRunMarkerKind) -> CameraRunTimelineMarker? {
        markers.first { $0.kind == kind }
    }

    public func window(for segment: CameraRunSegment) -> ClosedRange<Double>? {
        let start: CameraRunMarkerKind
        let end: CameraRunMarkerKind
        switch segment {
        case .preTalk:
            (start, end) = (.preTalkStart, .preTalkEnd)
        case .throwSegment:
            (start, end) = (.throwStart, .throwEnd)
        case .postTalk:
            (start, end) = (.postTalkStart, .postTalkEnd)
        }
        guard let startS = marker(for: start)?.timestampS,
              let endS = marker(for: end)?.timestampS else { return nil }
        return startS...endS
    }
}

nonisolated public enum CameraRunPermissionStatus: String, Codable, Equatable, Sendable {
    case notRequested
    case authorized
    case denied
    case restricted
    case unavailable
}

/// Photos is intentionally represented even though this prototype only
/// requests camera access.  Export and share integration must make that
/// permission explicit instead of silently writing to the photo library.
nonisolated public struct CameraRunPermissionSnapshot: Codable, Equatable, Sendable {
    public var camera: CameraRunPermissionStatus
    public var microphone: CameraRunPermissionStatus
    public var photos: CameraRunPermissionStatus

    public init(
        camera: CameraRunPermissionStatus = .notRequested,
        microphone: CameraRunPermissionStatus = .notRequested,
        photos: CameraRunPermissionStatus = .notRequested
    ) {
        self.camera = camera
        self.microphone = microphone
        self.photos = photos
    }
}

nonisolated public enum CameraRunClipSource: String, Codable, Equatable, Sendable {
    case replay
    case camera
    case composite
}

nonisolated public struct CameraRunTrim: Codable, Equatable, Sendable {
    public var startS: Double
    public var endS: Double

    public init(startS: Double, endS: Double) {
        self.startS = startS
        self.endS = endS
    }

    public static let zero = CameraRunTrim(startS: 0, endS: 0)

    public var durationS: Double { max(0, endS - startS) }

    public func clamped(to durationS: Double) -> CameraRunTrim {
        let limit = max(0, durationS.isFinite ? durationS : 0)
        let start = min(limit, max(0, self.startS.isFinite ? self.startS : 0))
        let end = min(limit, max(start, self.endS.isFinite ? self.endS : start))
        return CameraRunTrim(startS: start, endS: end)
    }
}

nonisolated public enum CameraRunLayoutPreset: String, Codable, CaseIterable, Equatable, Sendable {
    case vertical
    case pictureInPicture
}

nonisolated public struct CameraRunLayout: Codable, Equatable, Sendable {
    public var preset: CameraRunLayoutPreset
    public var width: Int
    public var height: Int

    public init(
        preset: CameraRunLayoutPreset = .vertical,
        width: Int = 1_080,
        height: Int = 1_920
    ) {
        self.preset = preset
        self.width = width
        self.height = height
    }

    public static let vertical = CameraRunLayout()

    public var aspectRatio: Double {
        guard width > 0 else { return 0 }
        return Double(height) / Double(width)
    }
}

nonisolated public enum CameraRunCaptionPlacement: String, Codable, CaseIterable, Equatable, Sendable {
    case top
    case center
    case bottom
}

nonisolated public struct CameraRunCaption: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var text: String
    /// Caption coordinates are in the original clip timebase, before trim.
    public var startS: Double
    public var endS: Double
    public var placement: CameraRunCaptionPlacement

    public init(
        id: UUID = UUID(),
        text: String,
        startS: Double,
        endS: Double,
        placement: CameraRunCaptionPlacement = .bottom
    ) {
        self.id = id
        self.text = text
        self.startS = startS
        self.endS = endS
        self.placement = placement
    }

    public func isVisible(atOriginalTimeS timeS: Double) -> Bool {
        !text.isEmpty && timeS >= startS && timeS <= endS
    }
}

nonisolated public struct CameraRunEdit: Codable, Equatable, Sendable {
    public var trim: CameraRunTrim
    public var layout: CameraRunLayout
    public var captions: [CameraRunCaption]

    public init(
        trim: CameraRunTrim,
        layout: CameraRunLayout = .vertical,
        captions: [CameraRunCaption] = []
    ) {
        self.trim = trim
        self.layout = layout
        self.captions = captions
    }
}

nonisolated public enum CameraRunDraftClipError: Error, Equatable, Sendable {
    case emptySource
    case invalidDuration
    case invalidTrim
}

/// Immutable source evidence plus a mutable edit description.  The source
/// replay frames and camera URL are never rewritten by trim/layout/caption
/// operations, so a later editor can always recover the original run.
nonisolated public struct CameraRunDraftClip: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let source: CameraRunClipSource
    public let originalDurationS: Double
    public let replayFrames: [ReplayFrame]
    public let cameraVideoURL: URL?
    public let timeline: CameraRunTimeline
    public private(set) var edit: CameraRunEdit

    public init(
        id: UUID = UUID(),
        source: CameraRunClipSource,
        originalDurationS: Double,
        replayFrames: [ReplayFrame] = [],
        cameraVideoURL: URL? = nil,
        timeline: CameraRunTimeline,
        edit: CameraRunEdit? = nil
    ) throws {
        guard originalDurationS.isFinite, originalDurationS >= 0 else {
            throw CameraRunDraftClipError.invalidDuration
        }
        guard !replayFrames.isEmpty || cameraVideoURL != nil else {
            throw CameraRunDraftClipError.emptySource
        }
        self.id = id
        self.source = source
        self.originalDurationS = originalDurationS
        self.replayFrames = replayFrames
        self.cameraVideoURL = cameraVideoURL
        self.timeline = timeline
        let initial = edit ?? CameraRunEdit(
            trim: CameraRunTrim(startS: 0, endS: originalDurationS)
        )
        let clamped = initial.trim.clamped(to: originalDurationS)
        guard clamped.durationS > 0 || originalDurationS == 0 else {
            throw CameraRunDraftClipError.invalidTrim
        }
        self.edit = CameraRunEdit(
            trim: clamped,
            layout: initial.layout,
            captions: initial.captions
        )
    }

    public init(
        replayFrames: [ReplayFrame],
        timeline: CameraRunTimeline,
        id: UUID = UUID(),
        edit: CameraRunEdit? = nil
    ) throws {
        guard let last = replayFrames.last else {
            throw CameraRunDraftClipError.emptySource
        }
        try self.init(
            id: id,
            source: .replay,
            originalDurationS: max(0, last.timestampMs / 1_000),
            replayFrames: replayFrames,
            timeline: timeline,
            edit: edit
        )
    }

    public var trimmedDurationS: Double { edit.trim.durationS }

    public func applying(_ edit: CameraRunEdit) throws -> CameraRunDraftClip {
        try CameraRunDraftClip(
            id: id,
            source: source,
            originalDurationS: originalDurationS,
            replayFrames: replayFrames,
            cameraVideoURL: cameraVideoURL,
            timeline: timeline,
            edit: edit
        )
    }
}

/// The editor is intentionally a small state holder.  It does not mutate
/// source frames, run detector logic, upload anything, or write a video.
@MainActor
@Observable
public final class CameraRunEditorModel {
    public private(set) var clip: CameraRunDraftClip
    public private(set) var lastError: CameraRunDraftClipError?

    public init(clip: CameraRunDraftClip) {
        self.clip = clip
    }

    @discardableResult
    public func setTrim(startS: Double, endS: Double) -> Bool {
        let edit = CameraRunEdit(
            trim: CameraRunTrim(startS: startS, endS: endS),
            layout: clip.edit.layout,
            captions: clip.edit.captions
        )
        return apply(edit)
    }

    @discardableResult
    public func setLayout(_ layout: CameraRunLayout) -> Bool {
        var edit = clip.edit
        edit.layout = layout
        return apply(edit)
    }

    @discardableResult
    public func setCaptions(_ captions: [CameraRunCaption]) -> Bool {
        var edit = clip.edit
        edit.captions = captions
        return apply(edit)
    }

    private func apply(_ edit: CameraRunEdit) -> Bool {
        do {
            clip = try clip.applying(edit)
            lastError = nil
            return true
        } catch let error as CameraRunDraftClipError {
            lastError = error
            return false
        } catch {
            lastError = .invalidTrim
            return false
        }
    }
}

nonisolated public enum CameraRunExportRenderPath: String, Codable, Equatable, Sendable {
    case replayFrames
    case existingCameraVideo
    case compositionRequired
}

nonisolated public enum CameraRunExportPlanError: Error, Equatable, Sendable {
    case emptySource
    case unsupportedFrameRate
    case invalidCanvas
    case invalidTrim
    case cameraCompositionNotImplemented
}

/// Deterministic, serializable intent for the export coordinator.  It is
/// separate from `ReplayVideoExportPlan` so a future camera compositor can
/// consume the same edit contract without changing replay rendering.
nonisolated public struct CameraRunExportPlan: Codable, Equatable, Sendable {
    public let clipID: UUID
    public let source: CameraRunClipSource
    public let renderPath: CameraRunExportRenderPath
    public let trim: CameraRunTrim
    public let layout: CameraRunLayout
    public let captions: [CameraRunCaption]
    public let frameRate: Int
    public let frameCount: Int
    public let durationS: Double

    public init(clip: CameraRunDraftClip, frameRate: Int = 30) throws {
        guard (1...60).contains(frameRate) else {
            throw CameraRunExportPlanError.unsupportedFrameRate
        }
        guard clip.originalDurationS > 0, !clip.replayFrames.isEmpty || clip.cameraVideoURL != nil else {
            throw CameraRunExportPlanError.emptySource
        }
        guard clip.edit.layout.width > 0, clip.edit.layout.height > 0 else {
            throw CameraRunExportPlanError.invalidCanvas
        }
        let trim = clip.edit.trim.clamped(to: clip.originalDurationS)
        guard trim.durationS > 0 else { throw CameraRunExportPlanError.invalidTrim }

        let renderPath: CameraRunExportRenderPath
        switch clip.source {
        case .replay:
            guard !clip.replayFrames.isEmpty else { throw CameraRunExportPlanError.emptySource }
            renderPath = .replayFrames
        case .camera:
            guard clip.cameraVideoURL != nil else { throw CameraRunExportPlanError.emptySource }
            renderPath = .existingCameraVideo
        case .composite:
            renderPath = .compositionRequired
        }

        self.clipID = clip.id
        self.source = clip.source
        self.renderPath = renderPath
        self.trim = trim
        self.layout = clip.edit.layout
        self.captions = clip.edit.captions
        self.frameRate = frameRate
        let cadenceCount = trim.durationS * Double(frameRate)
        self.frameCount = max(1, Int(ceil(cadenceCount - 1e-9)))
        self.durationS = trim.durationS
    }
}
