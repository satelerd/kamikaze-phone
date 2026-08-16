import Foundation
import KamikazeMotionApple
import KamikazeMotionCore
import Observation
import SwiftUI

nonisolated enum CalibrationLogicalAxis: String, Codable, CaseIterable, Sendable {
    case width
    case longEdge
    case screen

    var title: String {
        switch self {
        case .width: "WIDTH AXIS"
        case .longEdge: "LONG-EDGE AXIS"
        case .screen: "SCREEN AXIS"
        }
    }

    var instruction: String {
        switch self {
        case .width: "Rotate the top edge away from you by roughly 90°."
        case .longEdge: "Lift the right edge and roll the phone roughly 90°."
        case .screen: "Keep it flat and turn it clockwise roughly 90°."
        }
    }
}

nonisolated enum CalibrationRawAxis: String, Codable, CaseIterable, Sendable {
    case x
    case y
    case z
}

nonisolated struct AxisCalibrationObservation: Codable, Equatable, Sendable {
    let logicalAxis: CalibrationLogicalAxis
    let integratedDegrees: Vector3
    let durationMs: Double
    let sampleCount: Int
}

nonisolated struct AxisCalibrationMapping: Codable, Equatable, Sendable {
    let logicalAxis: CalibrationLogicalAxis
    let rawAxis: CalibrationRawAxis
    let sign: Int
    let measuredDegrees: Double
    let crossTalkPurity: Double
}

nonisolated struct AxisCalibrationProfile: Codable, Equatable, Sendable {
    static let version = "native-axis-check-v1"

    let id: String
    let version: String
    let createdAtISO8601: String
    let deviceName: String
    let operatingSystemVersion: String
    let mappings: [AxisCalibrationMapping]
    let confidence: Double
    let isReliable: Bool
}

nonisolated enum AxisCalibrationAnalyzer {
    static func analyze(
        _ observations: [AxisCalibrationObservation],
        deviceName: String,
        operatingSystemVersion: String,
        profileID: String = UUID().uuidString.lowercased(),
        createdAt: Date = Date()
    ) -> AxisCalibrationProfile? {
        guard observations.count == CalibrationLogicalAxis.allCases.count else { return nil }

        let mappings = observations.map { observation -> AxisCalibrationMapping in
            let values: [(CalibrationRawAxis, Double)] = [
                (.x, observation.integratedDegrees.x),
                (.y, observation.integratedDegrees.y),
                (.z, observation.integratedDegrees.z),
            ]
            let dominant = values.max { abs($0.1) < abs($1.1) } ?? (.x, 0)
            let total = values.reduce(0) { $0 + abs($1.1) }
            return AxisCalibrationMapping(
                logicalAxis: observation.logicalAxis,
                rawAxis: dominant.0,
                sign: dominant.1 < 0 ? -1 : 1,
                measuredDegrees: dominant.1,
                crossTalkPurity: total > 0 ? min(1, abs(dominant.1) / total) : 0
            )
        }
        let uniqueAxes = Set(mappings.map(\.rawAxis.rawValue)).count == mappings.count
        let minimumPurity = mappings.map(\.crossTalkPurity).min() ?? 0
        let minimumTravel = mappings.map { abs($0.measuredDegrees) }.min() ?? 0
        let travelConfidence = min(1, max(0, minimumTravel / 75))
        let confidence = min(minimumPurity, travelConfidence)

        return AxisCalibrationProfile(
            id: profileID,
            version: AxisCalibrationProfile.version,
            createdAtISO8601: ISO8601DateFormatter().string(from: createdAt),
            deviceName: deviceName,
            operatingSystemVersion: operatingSystemVersion,
            mappings: mappings,
            confidence: confidence,
            isReliable: uniqueAxes && minimumPurity >= 0.70 && minimumTravel >= 55
        )
    }
}

@MainActor
@Observable
final class ExpressCalibrationModel {
    enum Status: Equatable {
        case idle
        case streaming
        case recording
        case complete
        case unavailable
        case failed(String)
    }

    private enum Key {
        static let latestProfile = "latestNativeAxisCalibrationProfileV1"
    }

    private let source = CoreMotionSampleSource()
    private var streamTask: Task<Void, Never>?
    private var activeSamples: [MotionSampleV3] = []
    private var zeroAttitude: Quaternion?
    private var lastPoseUpdateS = 0.0

    private(set) var status: Status = .idle
    private(set) var attitude = Quaternion.identity
    private(set) var currentStepIndex = 0
    private(set) var observations: [AxisCalibrationObservation] = []
    private(set) var profile: AxisCalibrationProfile?
    private(set) var exportURL: URL?

    var currentAxis: CalibrationLogicalAxis {
        CalibrationLogicalAxis.allCases[min(currentStepIndex, CalibrationLogicalAxis.allCases.count - 1)]
    }

    var relativeAttitude: Quaternion {
        guard let zeroAttitude else { return attitude }
        return QuaternionMath.relative(from: zeroAttitude, to: attitude)
    }

    var isRecording: Bool { status == .recording }

    init(defaults: UserDefaults = .standard) {
        if let data = defaults.data(forKey: Key.latestProfile),
           let decoded = try? JSONDecoder().decode(AxisCalibrationProfile.self, from: data) {
            profile = decoded
        }
    }

    func start() {
        guard streamTask == nil else { return }
        guard source.isAvailable else {
            status = .unavailable
            return
        }
        status = .streaming
        streamTask = Task { @MainActor [weak self, source] in
            do {
                for try await sample in source.samples(configuration: MotionStreamConfiguration(
                    requestedFrequencyHz: 100,
                    ringBufferDurationS: 0.5,
                    timestampGapFactor: 1.5
                )) {
                    guard !Task.isCancelled, let self else { break }
                    self.ingest(sample)
                }
            } catch is CancellationError {
                // Expected when leaving the calibration screen.
            } catch {
                self?.status = .failed(error.localizedDescription)
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        source.stop()
        if status != .complete { status = .idle }
    }

    func zeroPose() {
        zeroAttitude = attitude
    }

    func beginStep() {
        guard status == .streaming else { return }
        zeroAttitude = attitude
        activeSamples = []
        status = .recording
    }

    func finishStep(defaults: UserDefaults = .standard) {
        guard status == .recording,
              let observation = Self.observation(axis: currentAxis, samples: activeSamples) else {
            activeSamples = []
            status = .streaming
            return
        }
        observations.append(observation)
        activeSamples = []
        if observations.count < CalibrationLogicalAxis.allCases.count {
            currentStepIndex = observations.count
            status = .streaming
            zeroAttitude = attitude
            return
        }

        profile = AxisCalibrationAnalyzer.analyze(
            observations,
            deviceName: "iPhone",
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
        if let profile,
           let data = try? JSONEncoder.sorted.encode(profile) {
            defaults.set(data, forKey: Key.latestProfile)
            exportURL = Self.makeExport(data: data)
        }
        status = .complete
    }

    func reset(defaults: UserDefaults = .standard) {
        observations = []
        currentStepIndex = 0
        profile = nil
        exportURL = nil
        activeSamples = []
        defaults.removeObject(forKey: Key.latestProfile)
        status = streamTask == nil ? .idle : .streaming
        zeroAttitude = attitude
    }

    private func ingest(_ sample: MotionSampleV3) {
        if status == .recording { activeSamples.append(sample) }
        if sample.timestampS - lastPoseUpdateS >= 1 / 60,
           let fused = sample.fusedAttitude {
            lastPoseUpdateS = sample.timestampS
            attitude = fused
        }
    }

    private nonisolated static func observation(
        axis: CalibrationLogicalAxis,
        samples: [MotionSampleV3]
    ) -> AxisCalibrationObservation? {
        guard samples.count >= 8,
              let first = samples.first,
              let last = samples.last,
              last.timestampS > first.timestampS else { return nil }
        var integratedX = 0.0
        var integratedY = 0.0
        var integratedZ = 0.0
        for (previous, current) in zip(samples, samples.dropFirst()) {
            let dt = current.timestampS - previous.timestampS
            guard dt > 0, dt < 0.1 else { continue }
            integratedX += (previous.rotationRateRadS.x + current.rotationRateRadS.x) * 0.5 * dt
            integratedY += (previous.rotationRateRadS.y + current.rotationRateRadS.y) * 0.5 * dt
            integratedZ += (previous.rotationRateRadS.z + current.rotationRateRadS.z) * 0.5 * dt
        }
        let radiansToDegrees = 180 / Double.pi
        return AxisCalibrationObservation(
            logicalAxis: axis,
            integratedDegrees: Vector3(
                x: integratedX * radiansToDegrees,
                y: integratedY * radiansToDegrees,
                z: integratedZ * radiansToDegrees
            ),
            durationMs: (last.timestampS - first.timestampS) * 1_000,
            sampleCount: samples.count
        )
    }

    private nonisolated static func makeExport(data: Data) -> URL? {
        let directory = FileManager.default.temporaryDirectory.appending(path: "KamikazeCalibration")
        let url = directory.appending(path: "kamikaze-axis-calibration-v1.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

struct ExpressCalibrationView: View {
    @State private var model = ExpressCalibrationModel()

    var body: some View {
        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.ion)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("EXPRESS\nAXIS CHECK.")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .tracking(-1.6)
                    Text("Three known movements validate which native X/Y/Z axis and direction the phone actually reports. Core Motion is already hardware-calibrated; this does not invent gain from an imperfect hand movement.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)

                    TimelineView(.animation(minimumInterval: 1 / 30, paused: model.status == .complete)) { context in
                        LivePhoneScene(
                            attitude: model.relativeAttitude,
                            accent: model.isRecording ? KamikazeTheme.hazard : KamikazeTheme.ion,
                            initialZoom: 0.48,
                            ghostAttitude: model.status == .complete
                                ? nil
                                : guideAttitude(at: context.date),
                            onLevel: model.zeroPose
                        )
                        .overlay(alignment: .topLeading) {
                            if model.status != .complete {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("GHOST = MOVEMENT GUIDE")
                                        .foregroundStyle(KamikazeTheme.volt)
                                    Text("SOLID = YOUR LIVE PHONE")
                                        .foregroundStyle(KamikazeTheme.frost)
                                }
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .padding(12)
                            }
                        }
                    }
                    .frame(height: 360)

                    if model.status == .complete, let profile = model.profile {
                        resultCard(profile)
                    } else {
                        stepCard
                        Button {
                            model.isRecording ? model.finishStep() : model.beginStep()
                        } label: {
                            Text(model.isRecording ? "STOP AT 90°" : "START THIS MOVE")
                                .font(.system(size: 17, weight: .black, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 72)
                        }
                        .adaptiveGlassButton(
                            prominent: true,
                            tint: model.isRecording ? KamikazeTheme.hazard : KamikazeTheme.ion
                        )
                        .disabled(model.status != .streaming && model.status != .recording)
                    }

                    if case let .failed(message) = model.status {
                        Text(message).foregroundStyle(KamikazeTheme.hazard)
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Express Calibration")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    private var stepCard: some View {
        GlassSurface(role: .instrumentHUD, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("STEP \(model.currentStepIndex + 1) / 3  ·  \(model.currentAxis.title)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.volt)
                Text(model.currentAxis.instruction)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                Text(model.isRecording
                    ? "Follow the translucent phone smoothly, hold at 90°, then tap STOP."
                    : "Start flat in your playing grip. Watch one ghost loop, tap START, then copy only that movement.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
                ProgressView(value: Double(model.observations.count), total: 3)
                    .tint(KamikazeTheme.volt)
            }
            .padding(18)
        }
    }

    /// A slow, repeating 0→90° example. The three poses are defined in the
    /// visual phone's local width/long-edge/screen axes; sensor mapping is
    /// still inferred independently from the player's measured raw values.
    private func guideAttitude(at date: Date) -> Quaternion {
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.0) / 3.0
        let linear: Double
        switch cycle {
        case ..<0.18: linear = 0
        case ..<0.68: linear = (cycle - 0.18) / 0.50
        default: linear = 1
        }
        let eased = linear * linear * (3 - 2 * linear)
        let angle = eased * Double.pi / 2
        let half = angle / 2
        switch model.currentAxis {
        case .width:
            return Quaternion(w: cos(half), x: sin(half), y: 0, z: 0)
        case .longEdge:
            return Quaternion(w: cos(half), x: 0, y: -sin(half), z: 0)
        case .screen:
            return Quaternion(w: cos(half), x: 0, y: 0, z: -sin(half))
        }
    }

    private func resultCard(_ profile: AxisCalibrationProfile) -> some View {
        GlassSurface(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text(profile.isReliable ? "AXES VERIFIED" : "RETAKE RECOMMENDED")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(profile.isReliable ? KamikazeTheme.volt : KamikazeTheme.hazard)
                Text("\(Int((profile.confidence * 100).rounded()))% MEASUREMENT QUALITY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                ForEach(profile.mappings, id: \.logicalAxis.rawValue) { mapping in
                    HStack {
                        Text(mapping.logicalAxis.title)
                        Spacer()
                        Text("RAW \(mapping.rawAxis.rawValue.uppercased())  ·  \(mapping.sign > 0 ? "+" : "−")  ·  \(Int(abs(mapping.measuredDegrees).rounded()))°")
                            .foregroundStyle(KamikazeTheme.volt)
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                Text("Saved as diagnostic evidence. Detector v0.2 remains frozen until a separate full bench and holdout confirm the mapping.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
                if let exportURL = model.exportURL {
                    ShareLink(item: exportURL) {
                        Label("EXPORT AXIS PROFILE", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .adaptiveGlassButton(tint: KamikazeTheme.volt)
                }
                Button("RETAKE ALL") { model.reset() }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .adaptiveGlassButton(tint: KamikazeTheme.hazard)
            }
            .padding(18)
        }
    }
}
