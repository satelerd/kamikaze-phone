import Foundation

public struct Vector3: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }
}

public struct Quaternion: Codable, Equatable, Sendable {
    public var w: Double
    public var x: Double
    public var y: Double
    public var z: Double

    public init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    public static let identity = Quaternion(w: 1, x: 0, y: 0, z: 0)
}

public struct MotionSample: Codable, Equatable, Sendable {
    public var timestampS: Double
    public var accelerationIncludingGravity: Vector3
    public var rotationRateDps: Vector3

    public init(
        timestampS: Double,
        accelerationIncludingGravity: Vector3,
        rotationRateDps: Vector3
    ) {
        self.timestampS = timestampS
        self.accelerationIncludingGravity = accelerationIncludingGravity
        self.rotationRateDps = rotationRateDps
    }
}

public struct RotationSummary: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var total: Double

    public init(x: Double, y: Double, z: Double, total: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.total = total
    }
}

public struct ReplayFrame: Equatable, Sendable {
    public var timestampMs: Double
    public var progress: Double
    public var quaternion: Quaternion
    public var accelG: Double
    public var gyroDps: Double

    public init(
        timestampMs: Double,
        progress: Double,
        quaternion: Quaternion,
        accelG: Double,
        gyroDps: Double
    ) {
        self.timestampMs = timestampMs
        self.progress = progress
        self.quaternion = quaternion
        self.accelG = accelG
        self.gyroDps = gyroDps
    }
}

public enum CaptureMode: String, Codable, Sendable {
    case auto
    case manual
}

public enum TriggerMode: String, Codable, Sendable {
    case freefall
    case gyro
}

public enum AttemptSource: String, Codable, Sendable {
    case sensor
    case synthetic
}

public struct ExpoAttemptV2: Codable, Equatable, Sendable {
    public var captureMode: CaptureMode?
    public var triggerMode: TriggerMode?
    public var id: String
    public var schemaVersion: Int
    public var source: AttemptSource
    public var recordedAtIso: String
    public var trick: String
    public var confidence: Double
    public var releaseTimestampS: Double
    public var catchTimestampS: Double
    public var airtimeMs: Double
    public var estimatedHeightM: Double
    public var rotationDegrees: RotationSummary
    public var peakRotationDps: Double
    public var peakCatchG: Double
    public var sampleCount: Int
    public var samples: [MotionSample]

    public init(
        captureMode: CaptureMode? = nil,
        triggerMode: TriggerMode? = nil,
        id: String,
        schemaVersion: Int = 2,
        source: AttemptSource,
        recordedAtIso: String,
        trick: String,
        confidence: Double,
        releaseTimestampS: Double,
        catchTimestampS: Double,
        airtimeMs: Double,
        estimatedHeightM: Double,
        rotationDegrees: RotationSummary,
        peakRotationDps: Double,
        peakCatchG: Double,
        sampleCount: Int,
        samples: [MotionSample]
    ) {
        self.captureMode = captureMode
        self.triggerMode = triggerMode
        self.id = id
        self.schemaVersion = schemaVersion
        self.source = source
        self.recordedAtIso = recordedAtIso
        self.trick = trick
        self.confidence = confidence
        self.releaseTimestampS = releaseTimestampS
        self.catchTimestampS = catchTimestampS
        self.airtimeMs = airtimeMs
        self.estimatedHeightM = estimatedHeightM
        self.rotationDegrees = rotationDegrees
        self.peakRotationDps = peakRotationDps
        self.peakCatchG = peakCatchG
        self.sampleCount = sampleCount
        self.samples = samples
    }
}

public struct ExpoLabelledCaptureV1: Codable, Equatable, Sendable {
    public var app: String
    public var expectedTrick: String
    public var recordedAttempt: ExpoAttemptV2
    public var schema: String

    public init(app: String, expectedTrick: String, recordedAttempt: ExpoAttemptV2, schema: String) {
        self.app = app
        self.expectedTrick = expectedTrick
        self.recordedAttempt = recordedAttempt
        self.schema = schema
    }
}
