import CoreGraphics
import CoreVideo
import Foundation
import Testing
@preconcurrency import AVFoundation
@testable import Kamikaze

/// Isolated from the heavier RealityKit/story compositor suite because the
/// simulator's media service can remain poisoned after an unrelated failed
/// AVFoundation session. This suite proves the exact player-facing path:
/// rendered H.264 + microphone audio -> 0.35x trick window -> playable MP4.
@Suite("Camera Run speed ramp export", .serialized)
struct CameraRunSpeedRampExportTests {
    @Test("0.35x exports with microphone audio")
    @MainActor
    func exportsPoint35WithAudio() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "kamikaze-speed-ramp-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appending(path: "source.mp4")
        try await makeSyntheticVideo(at: sourceURL)
        let microphoneURL = directory.appending(path: "microphone.caf")
        try makeSyntheticAudio(at: microphoneURL)
        let sourceWithAudio = try await CameraRunVideoComposer().attachAudio(
            videoURL: sourceURL,
            audioSourceURL: microphoneURL,
            audioStartS: 0,
            outputURL: directory.appending(path: "source-with-audio.mp4"),
            canvas: CGSize(width: 160, height: 284)
        )
        let artifact = try await CameraRunVideoComposer().applySpeedRamp(
            to: sourceWithAudio,
            sourceRange: CameraRunTrim(startS: 0.2, endS: 0.6),
            playbackRate: 0.35,
            outputURL: directory.appending(path: "slow.mp4")
        )

        let asset = AVURLAsset(url: artifact.url)
        let duration = try await asset.load(.duration).seconds
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(FileManager.default.fileExists(atPath: artifact.url.path))
        #expect(abs(duration - artifact.durationS) < 0.1)
        #expect(duration > 1.65)
        #expect(audioTracks.count == 1)
    }

    private func makeSyntheticVideo(at url: URL) async throws {
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

        for index in 0 ..< 12 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(1))
            }
            let buffer = try #require(makePixelBuffer(width: width, height: height))
            #expect(adaptor.append(
                buffer,
                withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 12)
            ))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }

    private func makeSyntheticAudio(at url: URL) throws {
        let sampleRate = 44_100.0
        let frames = AVAudioFrameCount(sampleRate)
        let format = try #require(AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ))
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frames
        ))
        buffer.frameLength = frames
        if let channel = buffer.floatChannelData?[0] {
            for index in 0 ..< Int(frames) {
                channel[index] = sin(Float(index) * 2 * .pi * 220 / Float(sampleRate)) * 0.05
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
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
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
