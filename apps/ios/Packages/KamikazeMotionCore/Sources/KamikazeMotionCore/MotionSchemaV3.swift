import Foundation

public enum MotionSchemaV3 {
    public static let version = 3
    public static let earthGravityMetersPerSecondSquared = 9.80665
}

/// Per-sample evidence quality. Flags describe missing or suspicious evidence;
/// they never repair or replace the raw values.
public struct MotionSampleQualityFlags: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let timestampDuplicate = Self(rawValue: 1 << 0)
    public static let timestampNonMonotonic = Self(rawValue: 1 << 1)
    public static let timestampGapBefore = Self(rawValue: 1 << 2)
    public static let sequenceGapBefore = Self(rawValue: 1 << 3)
    public static let missingUserAcceleration = Self(rawValue: 1 << 4)
    public static let missingGravity = Self(rawValue: 1 << 5)
    public static let missingFusedAttitude = Self(rawValue: 1 << 6)
    public static let legacyCombinedAcceleration = Self(rawValue: 1 << 7)
    public static let legacyImported = Self(rawValue: 1 << 8)
}

/// Unit-explicit raw evidence captured at the Apple/Core Motion boundary.
///
/// Native schema-v3 captures populate `userAccelerationG`, `gravityG` and
/// `fusedAttitude`. They are optional only so legacy schema-v2 evidence can be
/// imported honestly: v2 stored combined acceleration and did not store an
/// attitude quaternion.
public struct MotionSampleV3: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let timestampS: Double
    public let rotationRateRadS: Vector3
    public let userAccelerationG: Vector3?
    public let gravityG: Vector3?
    public let fusedAttitude: Quaternion?
    public let legacyAccelerationIncludingGravityG: Vector3?
    public let qualityFlags: MotionSampleQualityFlags

    public init(
        sequence: UInt64,
        timestampS: Double,
        rotationRateRadS: Vector3,
        userAccelerationG: Vector3,
        gravityG: Vector3,
        fusedAttitude: Quaternion,
        qualityFlags: MotionSampleQualityFlags = []
    ) {
        self.sequence = sequence
        self.timestampS = timestampS
        self.rotationRateRadS = rotationRateRadS
        self.userAccelerationG = userAccelerationG
        self.gravityG = gravityG
        self.fusedAttitude = fusedAttitude
        self.legacyAccelerationIncludingGravityG = nil
        self.qualityFlags = qualityFlags
    }

    init(
        importedLegacySequence sequence: UInt64,
        timestampS: Double,
        rotationRateRadS: Vector3,
        accelerationIncludingGravityG: Vector3,
        qualityFlags: MotionSampleQualityFlags
    ) {
        self.sequence = sequence
        self.timestampS = timestampS
        self.rotationRateRadS = rotationRateRadS
        self.userAccelerationG = nil
        self.gravityG = nil
        self.fusedAttitude = nil
        self.legacyAccelerationIncludingGravityG = accelerationIncludingGravityG
        self.qualityFlags = qualityFlags
    }

    public var accelerationIncludingGravityG: Vector3? {
        if let userAccelerationG, let gravityG {
            return Vector3(
                x: userAccelerationG.x + gravityG.x,
                y: userAccelerationG.y + gravityG.y,
                z: userAccelerationG.z + gravityG.z
            )
        }
        return legacyAccelerationIncludingGravityG
    }
}

public enum GripHand: String, Codable, Equatable, Sendable {
    case right
    case left
    case unknown
}

public enum CaptureOrientation: String, Codable, Equatable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
    case unknown
}

public enum MotionReferenceFrame: String, Codable, Equatable, Sendable {
    case xArbitraryZVertical
    case unknown
}

public struct CaptureDeviceMetadataV3: Codable, Equatable, Sendable {
    public let modelIdentifier: String?
    public let modelName: String?
    public let operatingSystemName: String
    public let operatingSystemVersion: String?
    public let operatingSystemBuild: String?

    public init(
        modelIdentifier: String?,
        modelName: String?,
        operatingSystemName: String,
        operatingSystemVersion: String?,
        operatingSystemBuild: String?
    ) {
        self.modelIdentifier = modelIdentifier
        self.modelName = modelName
        self.operatingSystemName = operatingSystemName
        self.operatingSystemVersion = operatingSystemVersion
        self.operatingSystemBuild = operatingSystemBuild
    }
}

public struct CaptureEnvironmentV3: Codable, Equatable, Sendable {
    public let device: CaptureDeviceMetadataV3
    public let gripHand: GripHand
    public let orientation: CaptureOrientation
    public let referenceFrame: MotionReferenceFrame
    public let requestedFrequencyHz: Double
    public let measuredFrequencyHz: Double?

    public init(
        device: CaptureDeviceMetadataV3,
        gripHand: GripHand,
        orientation: CaptureOrientation,
        referenceFrame: MotionReferenceFrame,
        requestedFrequencyHz: Double,
        measuredFrequencyHz: Double?
    ) {
        self.device = device
        self.gripHand = gripHand
        self.orientation = orientation
        self.referenceFrame = referenceFrame
        self.requestedFrequencyHz = requestedFrequencyHz
        self.measuredFrequencyHz = measuredFrequencyHz
    }
}

public struct AttemptBoundariesV3: Codable, Equatable, Sendable {
    public let captureStartS: Double
    public let captureEndS: Double
    public let motionStartS: Double
    public let motionEndS: Double
    public let releaseS: Double?
    public let catchS: Double?
    public let settledS: Double?

    public init(
        captureStartS: Double,
        captureEndS: Double,
        motionStartS: Double,
        motionEndS: Double,
        releaseS: Double?,
        catchS: Double?,
        settledS: Double?
    ) {
        self.captureStartS = captureStartS
        self.captureEndS = captureEndS
        self.motionStartS = motionStartS
        self.motionEndS = motionEndS
        self.releaseS = releaseS
        self.catchS = catchS
        self.settledS = settledS
    }
}

public struct ProcessingVersionsV3: Codable, Equatable, Sendable {
    public let calibrationProfileID: String?
    public let calibrationVersion: String?
    public let detectorVersion: String
    public let analysisVersion: String
    public let scoreVersion: String?

    public init(
        calibrationProfileID: String?,
        calibrationVersion: String?,
        detectorVersion: String,
        analysisVersion: String,
        scoreVersion: String?
    ) {
        self.calibrationProfileID = calibrationProfileID
        self.calibrationVersion = calibrationVersion
        self.detectorVersion = detectorVersion
        self.analysisVersion = analysisVersion
        self.scoreVersion = scoreVersion
    }
}

public enum RawSampleEncodingV3: String, Codable, Equatable, Sendable {
    case expoLabelledCaptureJSON
    case json
    case binaryPropertyList
}

public enum ChecksumAlgorithmV3: String, Codable, Equatable, Sendable {
    case sha256
}

/// Points to immutable evidence. Application persistence may relocate the
/// payload, but it must update the reference atomically and preserve checksum.
public struct RawSampleReferenceV3: Codable, Equatable, Sendable {
    public let relativePath: String
    public let encoding: RawSampleEncodingV3
    public let payloadSchemaVersion: Int
    public let sampleCount: Int
    public let checksumAlgorithm: ChecksumAlgorithmV3
    public let checksum: String

    public init(
        relativePath: String,
        encoding: RawSampleEncodingV3,
        payloadSchemaVersion: Int,
        sampleCount: Int,
        checksumAlgorithm: ChecksumAlgorithmV3 = .sha256,
        checksum: String
    ) {
        self.relativePath = relativePath
        self.encoding = encoding
        self.payloadSchemaVersion = payloadSchemaVersion
        self.sampleCount = sampleCount
        self.checksumAlgorithm = checksumAlgorithm
        self.checksum = checksum
    }
}

/// Preserves the derived schema-v2 result without pretending it was produced
/// by the native v3 analysis pipeline.
public struct ImportedExpoAnalysisV2: Codable, Equatable, Sendable {
    public let trick: String
    public let confidence: Double
    public let airtimeMs: Double
    public let estimatedHeightM: Double
    public let rotationDegrees: RotationSummary
    public let peakRotationDps: Double
    public let peakCatchG: Double
    public let declaredSampleCount: Int

    public init(attempt: ExpoAttemptV2) {
        self.trick = attempt.trick
        self.confidence = attempt.confidence
        self.airtimeMs = attempt.airtimeMs
        self.estimatedHeightM = attempt.estimatedHeightM
        self.rotationDegrees = attempt.rotationDegrees
        self.peakRotationDps = attempt.peakRotationDps
        self.peakCatchG = attempt.peakCatchG
        self.declaredSampleCount = attempt.sampleCount
    }
}

/// Indexed attempt metadata. Raw samples live in the separately checksummed
/// payload referenced by `rawSamples`.
public struct MotionAttemptV3: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let source: AttemptSource
    public let recordedAtISO8601: String
    public let captureMode: CaptureMode
    public let triggerMode: TriggerMode?
    public let boundaries: AttemptBoundariesV3
    public let environment: CaptureEnvironmentV3
    public let versions: ProcessingVersionsV3
    public let rawSamples: RawSampleReferenceV3
    public let importedExpoAnalysis: ImportedExpoAnalysisV2?

    public init(
        schemaVersion: Int = MotionSchemaV3.version,
        id: String,
        source: AttemptSource,
        recordedAtISO8601: String,
        captureMode: CaptureMode,
        triggerMode: TriggerMode?,
        boundaries: AttemptBoundariesV3,
        environment: CaptureEnvironmentV3,
        versions: ProcessingVersionsV3,
        rawSamples: RawSampleReferenceV3,
        importedExpoAnalysis: ImportedExpoAnalysisV2?
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.source = source
        self.recordedAtISO8601 = recordedAtISO8601
        self.captureMode = captureMode
        self.triggerMode = triggerMode
        self.boundaries = boundaries
        self.environment = environment
        self.versions = versions
        self.rawSamples = rawSamples
        self.importedExpoAnalysis = importedExpoAnalysis
    }
}

public struct MotionSamplePayloadV3: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let attemptID: String
    public let samples: [MotionSampleV3]

    public init(
        schemaVersion: Int = MotionSchemaV3.version,
        attemptID: String,
        samples: [MotionSampleV3]
    ) {
        self.schemaVersion = schemaVersion
        self.attemptID = attemptID
        self.samples = samples
    }
}

/// In-memory import result. Persistence writes `samplePayload` independently,
/// verifies its checksum and then stores `attempt` metadata.
public struct MotionCaptureV3: Codable, Equatable, Sendable {
    public let attempt: MotionAttemptV3
    public let samplePayload: MotionSamplePayloadV3

    public init(attempt: MotionAttemptV3, samplePayload: MotionSamplePayloadV3) {
        self.attempt = attempt
        self.samplePayload = samplePayload
    }
}

public struct ExpoAttemptV2MigrationContext: Equatable, Sendable {
    public let device: CaptureDeviceMetadataV3
    public let gripHand: GripHand
    public let orientation: CaptureOrientation
    public let referenceFrame: MotionReferenceFrame
    public let requestedFrequencyHz: Double
    public let versions: ProcessingVersionsV3
    public let rawSamples: RawSampleReferenceV3

    public init(
        device: CaptureDeviceMetadataV3,
        gripHand: GripHand,
        orientation: CaptureOrientation,
        referenceFrame: MotionReferenceFrame,
        requestedFrequencyHz: Double,
        versions: ProcessingVersionsV3,
        rawSamples: RawSampleReferenceV3
    ) {
        self.device = device
        self.gripHand = gripHand
        self.orientation = orientation
        self.referenceFrame = referenceFrame
        self.requestedFrequencyHz = requestedFrequencyHz
        self.versions = versions
        self.rawSamples = rawSamples
    }
}

public enum ExpoAttemptV2MigrationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case emptySamples
    case rawReferenceSampleCountMismatch(reference: Int, payload: Int)
}

public enum ExpoAttemptV2Migration {
    private static let degreesToRadians = Double.pi / 180

    public static func convert(
        _ legacy: ExpoAttemptV2,
        context: ExpoAttemptV2MigrationContext
    ) throws -> MotionCaptureV3 {
        guard legacy.schemaVersion == 2 else {
            throw ExpoAttemptV2MigrationError.unsupportedSchemaVersion(legacy.schemaVersion)
        }
        guard let first = legacy.samples.first, let last = legacy.samples.last else {
            throw ExpoAttemptV2MigrationError.emptySamples
        }
        guard context.rawSamples.sampleCount == legacy.samples.count else {
            throw ExpoAttemptV2MigrationError.rawReferenceSampleCountMismatch(
                reference: context.rawSamples.sampleCount,
                payload: legacy.samples.count
            )
        }

        let expectedIntervalS = context.requestedFrequencyHz > 0
            ? 1 / context.requestedFrequencyHz
            : nil
        var previousTimestampS: Double?
        let samples = legacy.samples.enumerated().map { index, sample in
            var flags: MotionSampleQualityFlags = [
                .legacyImported,
                .legacyCombinedAcceleration,
                .missingUserAcceleration,
                .missingGravity,
                .missingFusedAttitude,
            ]
            if let previousTimestampS {
                let intervalS = sample.timestampS - previousTimestampS
                if intervalS == 0 { flags.insert(.timestampDuplicate) }
                if intervalS < 0 { flags.insert(.timestampNonMonotonic) }
                if let expectedIntervalS,
                   intervalS > expectedIntervalS * 1.5 {
                    flags.insert(.timestampGapBefore)
                }
            }
            previousTimestampS = sample.timestampS

            return MotionSampleV3(
                importedLegacySequence: UInt64(index),
                timestampS: sample.timestampS,
                rotationRateRadS: Vector3(
                    x: sample.rotationRateDps.x * degreesToRadians,
                    y: sample.rotationRateDps.y * degreesToRadians,
                    z: sample.rotationRateDps.z * degreesToRadians
                ),
                accelerationIncludingGravityG: Vector3(
                    x: sample.accelerationIncludingGravity.x
                        / MotionSchemaV3.earthGravityMetersPerSecondSquared,
                    y: sample.accelerationIncludingGravity.y
                        / MotionSchemaV3.earthGravityMetersPerSecondSquared,
                    z: sample.accelerationIncludingGravity.z
                        / MotionSchemaV3.earthGravityMetersPerSecondSquared
                ),
                qualityFlags: flags
            )
        }

        let measuredFrequencyHz = measuredFrequency(for: legacy.samples)
        let manual = (legacy.captureMode ?? .auto) == .manual
        let boundaries = AttemptBoundariesV3(
            captureStartS: first.timestampS,
            captureEndS: last.timestampS,
            motionStartS: legacy.releaseTimestampS,
            motionEndS: legacy.catchTimestampS,
            releaseS: manual ? nil : legacy.releaseTimestampS,
            catchS: manual ? nil : legacy.catchTimestampS,
            settledS: nil
        )
        let environment = CaptureEnvironmentV3(
            device: context.device,
            gripHand: context.gripHand,
            orientation: context.orientation,
            referenceFrame: context.referenceFrame,
            requestedFrequencyHz: context.requestedFrequencyHz,
            measuredFrequencyHz: measuredFrequencyHz
        )
        let attempt = MotionAttemptV3(
            id: legacy.id,
            source: legacy.source,
            recordedAtISO8601: legacy.recordedAtIso,
            captureMode: legacy.captureMode ?? .auto,
            triggerMode: legacy.triggerMode,
            boundaries: boundaries,
            environment: environment,
            versions: context.versions,
            rawSamples: context.rawSamples,
            importedExpoAnalysis: ImportedExpoAnalysisV2(attempt: legacy)
        )
        return MotionCaptureV3(
            attempt: attempt,
            samplePayload: MotionSamplePayloadV3(attemptID: legacy.id, samples: samples)
        )
    }

    private static func measuredFrequency(for samples: [MotionSample]) -> Double? {
        guard samples.count > 1 else { return nil }
        let positiveIntervals = zip(samples, samples.dropFirst()).compactMap { previous, current in
            let interval = current.timestampS - previous.timestampS
            return interval > 0 ? interval : nil
        }
        guard !positiveIntervals.isEmpty else { return nil }
        let elapsedS = positiveIntervals.reduce(0, +)
        return elapsedS > 0 ? Double(positiveIntervals.count) / elapsedS : nil
    }
}
