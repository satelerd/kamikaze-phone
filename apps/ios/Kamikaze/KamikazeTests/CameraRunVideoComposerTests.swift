import CoreGraphics
import CoreVideo
import Foundation
import KamikazeMotionCore
import Testing
import UIKit
@preconcurrency import AVFoundation
@testable import Kamikaze

// AVAssetExportSession and the off-screen RealityKit snapshotter both use
// simulator media services. Running these integration tests concurrently can
// make the service cancel an otherwise valid export with "Operation Stopped".
@Suite("Camera Run video composition", .serialized)
struct CameraRunVideoComposerTests {
    private let canvas = CGSize(width: 1_080, height: 1_920)

    @Test("single camera fills the output")
    func singleCameraFillsCanvas() {
        let rectangles = CameraRunVideoLayoutPlanner.rectangles(
            preset: .pictureInPicture,
            canvas: canvas,
            positions: [.front]
        )

        #expect(rectangles[.front] == CGRect(origin: .zero, size: canvas))
        #expect(rectangles[.rear] == nil)
    }

    @Test("vertical layout preserves both cameras")
    func verticalStack() {
        let rectangles = CameraRunVideoLayoutPlanner.rectangles(
            preset: .vertical,
            canvas: canvas,
            positions: [.front, .rear]
        )

        #expect(rectangles[.rear] == CGRect(x: 0, y: 960, width: 1_080, height: 960))
        #expect(rectangles[.front] == CGRect(x: 0, y: 0, width: 1_080, height: 960))
        #expect(rectangles.values.reduce(0) { $0 + $1.width * $1.height } == canvas.width * canvas.height)
    }

    @Test("picture in picture keeps rear full and front inset")
    func pictureInPicture() {
        let rectangles = CameraRunVideoLayoutPlanner.rectangles(
            preset: .pictureInPicture,
            canvas: canvas,
            positions: [.rear, .front]
        )

        #expect(rectangles[.rear] == CGRect(origin: .zero, size: canvas))
        let front = try! #require(rectangles[.front])
        #expect(front.width == 378)
        #expect(front.minX > canvas.width / 2)
        #expect(front.maxX < canvas.width)
        #expect(front.maxY < canvas.height)
    }

    @Test("aspect fill covers the destination for portrait input")
    func aspectFillCoverage() {
        let destination = CGRect(x: 0, y: 0, width: 540, height: 960)
        let transform = CameraRunVideoComposer.aspectFillTransform(
            naturalSize: CGSize(width: 1_080, height: 1_920),
            preferredTransform: .identity,
            destination: destination
        )
        let rendered = CGRect(x: 0, y: 0, width: 1_080, height: 1_920).applying(transform)

        #expect(abs(rendered.minX - destination.minX) < 0.01)
        #expect(abs(rendered.minY - destination.minY) < 0.01)
        #expect(abs(rendered.width - destination.width) < 0.01)
        #expect(abs(rendered.height - destination.height) < 0.01)
    }

    @Test("story cut keeps camera intro and reaction around replay")
    func storyCutTimeline() throws {
        let plan = try CameraRunReplayTimelinePlan.make(
            cameraDurationS: 10,
            replayDurationS: 2,
            transition: CameraRunReplayTransition(
                entryProgress: 0.3,
                resumeProgress: 0.7,
                style: .cut,
                durationS: 0.4
            )
        )

        #expect(abs(plan.cameraIntroDurationS - 3) < 0.000_001)
        #expect(abs(plan.cameraSkippedDurationS - 4) < 0.000_001)
        #expect(abs(plan.cameraOutroDurationS - 3) < 0.000_001)
        #expect(abs(plan.replayStartS - 3) < 0.000_001)
        #expect(abs(plan.cameraOutroStartS - 5) < 0.000_001)
        #expect(plan.entryTransitionDurationS == 0)
        #expect(plan.exitTransitionDurationS == 0)
        #expect(plan.outputDurationS == 8)
    }

    @Test("dissolves overlap sources without overlapping each other")
    func storyDissolveTimeline() throws {
        let plan = try CameraRunReplayTimelinePlan.make(
            cameraDurationS: 10,
            replayDurationS: 2,
            transition: CameraRunReplayTransition(
                entryProgress: 0.3,
                resumeProgress: 0.7,
                style: .crossDissolve,
                durationS: 0.5
            )
        )

        #expect(plan.replayStartS == 2.5)
        #expect(plan.cameraOutroStartS == 4)
        #expect(plan.entryTransitionDurationS == 0.5)
        #expect(plan.exitTransitionDurationS == 0.5)
        #expect(plan.outputDurationS == 7)

        let shortReplay = try CameraRunReplayTimelinePlan.make(
            cameraDurationS: 10,
            replayDurationS: 0.4,
            transition: CameraRunReplayTransition(
                entryProgress: 0.3,
                resumeProgress: 0.7,
                style: .crossDissolve,
                durationS: 1
            )
        )
        #expect(shortReplay.entryTransitionDurationS == 0.2)
        #expect(shortReplay.exitTransitionDurationS == 0.2)
    }

    @Test("real AVFoundation export combines two source videos")
    func exportsDualCameraVideo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "kamikaze-composer-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rearURL = directory.appending(path: "rear.mp4")
        let frontURL = directory.appending(path: "front.mp4")
        try await makeSyntheticVideo(at: rearURL, color: .init(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
        try await makeSyntheticVideo(at: frontURL, color: .init(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))

        let outputURL = directory.appending(path: "final.mp4")
        let artifact = try await CameraRunVideoComposer().export(CameraRunVideoCompositionRequest(
            sources: [
                CameraRunVideoSource(position: .rear, url: rearURL),
                CameraRunVideoSource(position: .front, url: frontURL)
            ],
            edit: CameraRunEdit(
                trim: CameraRunTrim(startS: 0.1, endS: 0.8),
                layout: CameraRunLayout(preset: .pictureInPicture, width: 320, height: 568),
                captions: [CameraRunCaption(text: "PHONE FLIP", startS: 0.1, endS: 0.8)]
            ),
            outputURL: outputURL,
            frameRate: 24
        ))

        #expect(FileManager.default.fileExists(atPath: artifact.url.path))
        #expect(artifact.sourceCount == 2)
        #expect(abs(artifact.durationS - 0.7) < 0.01)
        let outputAsset = AVURLAsset(url: artifact.url)
        let tracks = try await outputAsset.loadTracks(withMediaType: .video)
        let duration = try await outputAsset.load(.duration)
        #expect(tracks.count == 1)
        #expect(CMTimeGetSeconds(duration) > 0.65)
    }

    @Test("real export dissolves camera into replay and returns to camera")
    @MainActor
    func exportsStoryCut() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "kamikaze-story-cut-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cameraURL = directory.appending(path: "camera.mp4")
        let replayURL = directory.appending(path: "replay.mp4")
        try await makeSyntheticVideo(at: cameraURL, color: .init(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
        try await makeSyntheticVideo(at: replayURL, color: .init(red: 0.7, green: 0.9, blue: 0.1, alpha: 1))

        let outputURL = directory.appending(path: "story.mp4")
        let artifact = try await CameraRunVideoComposer().composeReplay(
            cameraArtifact: CameraRunVideoCompositionArtifact(
                url: cameraURL,
                durationS: 1,
                canvas: CGSize(width: 160, height: 284),
                sourceCount: 1
            ),
            replayArtifact: ReplayVideoArtifact(
                url: replayURL,
                durationS: 1,
                frameCount: 12,
                canvas: ReplayVideoCanvas(width: 160, height: 284)
            ),
            transition: CameraRunReplayTransition(
                entryProgress: 0.3,
                resumeProgress: 0.7,
                style: .crossDissolve,
                durationS: 0.1
            ),
            outputURL: outputURL,
            frameRate: 24
        )

        #expect(FileManager.default.fileExists(atPath: artifact.url.path))
        #expect(artifact.durationS > 1.35)
        #expect(artifact.durationS < 1.7)
        let outputAsset = AVURLAsset(url: artifact.url)
        let tracks = try await outputAsset.loadTracks(withMediaType: .video)
        let duration = try await outputAsset.load(.duration)
        #expect(tracks.count == 1)
        #expect(abs(CMTimeGetSeconds(duration) - artifact.durationS) < 0.1)
    }

    @Test("RealityKit renderer snapshots the configured 3D phone")
    @MainActor
    func realityKitReplaySnapshot() async throws {
        let renderer = RealityKitReplayFrameRenderer(
            appearance: .default,
            accent: .systemBlue
        )
        let image = try await renderer.image(
            for: ReplayFrame(
                timestampMs: 120,
                progress: 0.5,
                quaternion: Quaternion(w: 0.9239, x: 0, y: 0.3827, z: 0),
                accelG: 0.2,
                gyroDps: 540
            ),
            canvas: ReplayVideoCanvas(width: 360, height: 640),
            caption: nil
        )

        #expect(image.width == 360)
        #expect(image.height == 640)
    }

    private func makeSyntheticVideo(at url: URL, color: CGColor) async throws {
        let width = 160
        let height = 284
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        #expect(writer.canAdd(input))
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for index in 0..<12 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(1))
            }
            let buffer = try #require(makePixelBuffer(width: width, height: height, color: color))
            #expect(adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 12)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }

    private func makePixelBuffer(width: Int, height: Int, color: CGColor) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGBitmapContextCompatibilityKey as String: true] as CFDictionary,
            &buffer
        ) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
