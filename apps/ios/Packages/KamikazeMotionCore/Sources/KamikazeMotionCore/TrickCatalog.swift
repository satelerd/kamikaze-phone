import Foundation

public enum TrickCatalogVersion {
    public static let provisionalV1 = "trick-catalog-v0.1-uncalibrated"
}

public enum BuiltInTrickID: String, Codable, CaseIterable, Equatable, Sendable {
    case phoneFlip = "phone-flip"
    case reversePhoneFlip = "reverse-phone-flip"
    case frontFlip = "front-flip"
    case backFlip = "back-flip"
    case backsideShuvit = "backside-shuvit"
    case frontsideShuvit = "frontside-shuvit"
    case straightAir = "straight-air"
    case threeSixtyFlip = "360-flip"
    case laserFlip = "laser-flip"
}

public enum TrickFamily: String, Codable, Equatable, Sendable {
    case air
    case flip
    case shuvit
    case combo
}

public struct TrickDefinition: Codable, Equatable, Sendable {
    public let id: BuiltInTrickID
    public let displayName: String
    public let family: TrickFamily
    public let targetRotationDegrees: Vector3
    public let referenceDurationMs: Double
    public let requiresSeparableAxes: Bool

    public init(
        id: BuiltInTrickID,
        displayName: String,
        family: TrickFamily,
        targetRotationDegrees: Vector3,
        referenceDurationMs: Double,
        requiresSeparableAxes: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.family = family
        self.targetRotationDegrees = targetRotationDegrees
        self.referenceDurationMs = referenceDurationMs
        self.requiresSeparableAxes = requiresSeparableAxes
    }
}

public struct TrickCatalog: Codable, Equatable, Sendable {
    public let version: String
    public let gripHand: GripHand
    public let definitions: [TrickDefinition]

    public init(version: String, gripHand: GripHand, definitions: [TrickDefinition]) {
        self.version = version
        self.gripHand = gripHand
        self.definitions = definitions
    }

    /// Mirrors only player-facing Y/Z semantics. Raw sensor evidence remains untouched.
    public static func provisional(gripHand: GripHand, includesUncalibratedCombos: Bool = true) -> Self {
        let semanticSign = gripHand == .left ? -1.0 : 1.0
        let y: (Double) -> Double = { $0 * semanticSign }
        let z: (Double) -> Double = { $0 * semanticSign }
        var definitions = [
            TrickDefinition(
                id: .straightAir,
                displayName: "STRAIGHT AIR",
                family: .air,
                targetRotationDegrees: Vector3(x: 0, y: 0, z: 0),
                referenceDurationMs: 520
            ),
            TrickDefinition(
                id: .phoneFlip,
                displayName: "PHONE FLIP",
                family: .flip,
                targetRotationDegrees: Vector3(x: 0, y: y(360), z: 0),
                referenceDurationMs: 780
            ),
            TrickDefinition(
                id: .reversePhoneFlip,
                displayName: "REVERSE PHONE FLIP",
                family: .flip,
                targetRotationDegrees: Vector3(x: 0, y: y(-360), z: 0),
                referenceDurationMs: 780
            ),
            TrickDefinition(
                id: .frontFlip,
                displayName: "FRONT FLIP",
                family: .flip,
                targetRotationDegrees: Vector3(x: 360, y: 0, z: 0),
                referenceDurationMs: 620
            ),
            TrickDefinition(
                id: .backFlip,
                displayName: "BACK FLIP",
                family: .flip,
                targetRotationDegrees: Vector3(x: -360, y: 0, z: 0),
                referenceDurationMs: 620
            ),
            TrickDefinition(
                id: .backsideShuvit,
                displayName: "BACKSIDE SHUVIT",
                family: .shuvit,
                targetRotationDegrees: Vector3(x: 0, y: 0, z: z(180)),
                referenceDurationMs: 520
            ),
            TrickDefinition(
                id: .frontsideShuvit,
                displayName: "FRONTSIDE SHUVIT",
                family: .shuvit,
                targetRotationDegrees: Vector3(x: 0, y: 0, z: z(-180)),
                referenceDurationMs: 520
            ),
        ]
        if includesUncalibratedCombos {
            definitions += [
                TrickDefinition(
                    id: .threeSixtyFlip,
                    displayName: "360 FLIP",
                    family: .combo,
                    targetRotationDegrees: Vector3(x: 0, y: y(360), z: z(360)),
                    referenceDurationMs: 820,
                    requiresSeparableAxes: true
                ),
                TrickDefinition(
                    id: .laserFlip,
                    displayName: "LASER FLIP",
                    family: .combo,
                    targetRotationDegrees: Vector3(x: 0, y: y(-360), z: z(-360)),
                    referenceDurationMs: 820,
                    requiresSeparableAxes: true
                ),
            ]
        }
        return Self(version: TrickCatalogVersion.provisionalV1, gripHand: gripHand, definitions: definitions)
    }
}

public enum TrickRecognitionStatus: String, Codable, Equatable, Sendable {
    case recognized
    case review
    case unknown
    case invalid
}

public struct TrickMatchCandidate: Equatable, Sendable {
    public let definition: TrickDefinition
    /// A transparent rules fit in [0, 1]. It is not a probability or calibrated confidence.
    public let presentationFit: Double
    public let rotationFit: Double
    public let axisPurity: Double
    public let durationFit: Double
    public let minimumAxisCoverage: Double
    public let axesAreSeparable: Bool

    public init(
        definition: TrickDefinition,
        presentationFit: Double,
        rotationFit: Double,
        axisPurity: Double,
        durationFit: Double,
        minimumAxisCoverage: Double,
        axesAreSeparable: Bool
    ) {
        self.definition = definition
        self.presentationFit = presentationFit
        self.rotationFit = rotationFit
        self.axisPurity = axisPurity
        self.durationFit = durationFit
        self.minimumAxisCoverage = minimumAxisCoverage
        self.axesAreSeparable = axesAreSeparable
    }
}

public struct TrickMatchResult: Equatable, Sendable {
    public let status: TrickRecognitionStatus
    public let policyVersion: String
    public let catalogVersion: String
    public let features: MotionFeatures?
    public let featureIssues: [MotionFeatureIssue]
    public let candidates: [TrickMatchCandidate]

    public init(
        status: TrickRecognitionStatus,
        policyVersion: String,
        catalogVersion: String,
        features: MotionFeatures?,
        featureIssues: [MotionFeatureIssue],
        candidates: [TrickMatchCandidate]
    ) {
        self.status = status
        self.policyVersion = policyVersion
        self.catalogVersion = catalogVersion
        self.features = features
        self.featureIssues = featureIssues
        self.candidates = candidates
    }
}

public struct TrickMatchingPolicy: Equatable, Sendable {
    public static let provisionalVersion = "rule-matcher-v0.1-uncalibrated"

    /// Presentation hypotheses only. They must be tuned against labelled/holdout fixtures.
    public var recognizedPresentationFit = 0.75
    public var reviewPresentationFit = 0.52
    public var recognizedMinimumMargin = 0.08
    public var comboMinimumAxisCoverage = 0.70
    public var comboMinimumAxisEfficiency = 0.58

    public init() {}
}

public struct TrickMatcher: Sendable {
    public let policy: TrickMatchingPolicy

    public init(policy: TrickMatchingPolicy = .init()) {
        self.policy = policy
    }

    public func match(
        attempt: SegmentedAttemptV3,
        catalog: TrickCatalog
    ) -> TrickMatchResult {
        let extraction = MotionFeatureExtractor.extract(from: attempt)
        guard let features = extraction.features else {
            return TrickMatchResult(
                status: .invalid,
                policyVersion: TrickMatchingPolicy.provisionalVersion,
                catalogVersion: catalog.version,
                features: nil,
                featureIssues: extraction.issues,
                candidates: []
            )
        }

        let candidates = catalog.definitions
            .map { score(features: features, definition: $0) }
            .sorted {
                if $0.presentationFit == $1.presentationFit {
                    return $0.definition.id.rawValue < $1.definition.id.rawValue
                }
                return $0.presentationFit > $1.presentationFit
            }
        let top = Array(candidates.prefix(3))
        let bestFit = top.first?.presentationFit ?? 0
        let margin = bestFit - (top.dropFirst().first?.presentationFit ?? 0)
        let status: TrickRecognitionStatus
        if bestFit >= policy.recognizedPresentationFit,
           margin >= policy.recognizedMinimumMargin,
           top.first?.axesAreSeparable != false,
           !attempt.timedOut {
            status = .recognized
        } else if bestFit >= policy.reviewPresentationFit {
            status = .review
        } else {
            status = .unknown
        }

        return TrickMatchResult(
            status: status,
            policyVersion: TrickMatchingPolicy.provisionalVersion,
            catalogVersion: catalog.version,
            features: features,
            featureIssues: extraction.issues,
            candidates: top
        )
    }

    private func score(features: MotionFeatures, definition: TrickDefinition) -> TrickMatchCandidate {
        let target = definition.targetRotationDegrees
        let measured = features.signedRotationDegrees
        let path = features.angularPathDegrees
        let activeAxes = axes.filter { abs(value(target, axis: $0)) >= 1 }
        let inactiveAxes = axes.filter { abs(value(target, axis: $0)) < 1 }

        if activeAxes.isEmpty {
            let rotationFit = clamp(1 - features.totalAngularPathDegrees / 180)
            let speedFit = clamp(1 - features.peakGyroDps / 360)
            let durationFit = durationFit(features.motionDurationMs, definition.referenceDurationMs)
            return TrickMatchCandidate(
                definition: definition,
                presentationFit: clamp(rotationFit * 0.72 + speedFit * 0.20 + durationFit * 0.08),
                rotationFit: rotationFit,
                axisPurity: rotationFit,
                durationFit: durationFit,
                minimumAxisCoverage: rotationFit,
                axesAreSeparable: true
            )
        }

        let axisFits = activeAxes.map { axis -> Double in
            let expected = value(target, axis: axis)
            let actual = value(measured, axis: axis)
            guard actual == 0 || actual.sign == expected.sign else { return 0 }
            return clamp(1 - abs(actual - expected) / max(abs(expected), 180))
        }
        let coverage = activeAxes.map { axis -> Double in
            let expected = value(target, axis: axis)
            let actual = value(measured, axis: axis)
            guard actual == 0 || actual.sign == expected.sign else { return 0 }
            return clamp(abs(actual) / abs(expected))
        }
        let activePath = activeAxes.reduce(0) { $0 + value(path, axis: $1) }
        let inactivePath = inactiveAxes.reduce(0) { $0 + value(path, axis: $1) }
        let axisPurity = activePath + inactivePath > 0
            ? clamp(activePath / (activePath + inactivePath))
            : 0
        let rotationFit = axisFits.reduce(0, +) / Double(axisFits.count)
        let minimumCoverage = coverage.min() ?? 0
        let durationFit = durationFit(features.motionDurationMs, definition.referenceDurationMs)
        var presentationFit = clamp(
            rotationFit * 0.68
                + axisPurity * 0.18
                + durationFit * 0.08
                + features.rotationEfficiency * 0.06
        )
        presentationFit *= 0.25 + 0.75 * minimumCoverage

        let activeEfficiencies = activeAxes.map { axis -> Double in
            let axisPath = value(path, axis: axis)
            return axisPath > 0 ? clamp(abs(value(measured, axis: axis)) / axisPath) : 0
        }
        let axesAreSeparable = !definition.requiresSeparableAxes || (
            minimumCoverage >= policy.comboMinimumAxisCoverage
                && activeEfficiencies.allSatisfy { $0 >= policy.comboMinimumAxisEfficiency }
        )
        if !axesAreSeparable {
            // A partial/noisy component can remain visible for review, but cannot win as a combo.
            presentationFit = min(presentationFit * 0.35, policy.reviewPresentationFit - 0.01)
        }

        return TrickMatchCandidate(
            definition: definition,
            presentationFit: presentationFit,
            rotationFit: rotationFit,
            axisPurity: axisPurity,
            durationFit: durationFit,
            minimumAxisCoverage: minimumCoverage,
            axesAreSeparable: axesAreSeparable
        )
    }

    private func durationFit(_ actual: Double, _ reference: Double) -> Double {
        clamp(1 - abs(actual - reference) / max(reference, 350))
    }

    private func value(_ vector: Vector3, axis: Axis) -> Double {
        switch axis {
        case .x: vector.x
        case .y: vector.y
        case .z: vector.z
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private enum Axis: CaseIterable { case x, y, z }
    private var axes: [Axis] { Axis.allCases }
}
