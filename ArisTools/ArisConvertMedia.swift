//
//  ArisConvertMedia.swift
//  aris-tools
//
//  Video and sound for `convert`, `merge` and `compress`, with AVFoundation only (no ffmpeg): MOV and MP4 into each
//  other (the streams copied when the new container takes them), the sound alone as M4A, clips of one kind joined,
//  and smaller copies through Apple's export presets. Every export has a time limit (ArisConvertWords.mediaLimit):
//  past it the export is cancelled and its file removed.
//

import AVFoundation
import Foundation

enum ArisConvertMedia {
    enum Output: Equatable {
        case video(AVFileType)
        case sound
    }

    static func fileType(_ format: String) -> AVFileType? {
        switch format {
        case "mp4": return .mp4
        case "mov": return .mov
        case "m4a": return .m4a
        default: return nil
        }
    }

    /// The export preset a smaller video takes: up to `maxSide` pixels tall (a 1080p HEVC copy without one).
    static func compressPreset(maxSide: Int?) -> String {
        guard let maxSide else { return AVAssetExportPresetHEVC1920x1080 }
        if maxSide <= 480 { return AVAssetExportPreset640x480 }
        if maxSide <= 540 { return AVAssetExportPreset960x540 }
        if maxSide <= 720 { return AVAssetExportPreset1280x720 }
        return AVAssetExportPresetHEVC1920x1080
    }

    /// Converts or joins `sources` into `url`. `preset`: nil copies the streams when the container takes them (else the
    /// highest quality), or the given preset (a smaller copy). Waits at most `limit` seconds.
    static func export(_ sources: [URL], labels: [String], to url: URL, output: Output, preset: String?, limit: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(limit)
        let asset: AVAsset = try blocking(until: deadline) { try await composed(sources, labels: labels, sound: output == .sound) }
        let type: AVFileType
        let presets: [String]
        switch output {
        case .sound:
            type = .m4a
            presets = [AVAssetExportPresetAppleM4A]
        case .video(let fileType):
            type = fileType
            presets = preset.map { [$0, AVAssetExportPresetMediumQuality] } ?? [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        }
        var lastProblem = "couldn't make it"
        for name in presets {
            let compatible: Bool = try blocking(until: deadline) {
                await AVAssetExportSession.compatibility(ofExportPreset: name, with: asset, outputFileType: type)
            }
            guard compatible, let session = AVAssetExportSession(asset: asset, presetName: name) else { continue }
            try? FileManager.default.removeItem(at: url)
            session.shouldOptimizeForNetworkUse = type != .mov
            do {
                try blocking(until: deadline, timedOut: "it took longer than \(Int(limit / 60)) minutes, so Aris stopped (nothing was made)") {
                    try await session.export(to: url, as: type)
                }
                return
            } catch let stopped as ArisConvertError where stopped.message.hasPrefix("it took longer") {
                try? FileManager.default.removeItem(at: url)
                throw stopped
            } catch {
                lastProblem = error.localizedDescription
                try? FileManager.default.removeItem(at: url)
            }
        }
        throw ArisConvertError("couldn't export it", detail: lastProblem)
    }

    /// One asset, or the clips one after another. `sound`: only the sound is wanted, and it must be there.
    private static func composed(_ sources: [URL], labels: [String], sound: Bool) async throws -> AVAsset {
        let assets = sources.map { AVURLAsset(url: $0) }
        for (asset, source) in zip(assets, labels) {
            let video = try await asset.loadTracks(withMediaType: .video)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            if sound, audio.isEmpty { throw ArisConvertError("\(source) has no sound in it") }
            if !sound, video.isEmpty { throw ArisConvertError("\(source) has no picture in it") }
        }
        guard assets.count > 1 else { return assets[0] }
        let composition = AVMutableComposition()
        for (asset, source) in zip(assets, labels) {
            let duration = try await asset.load(.duration)
            do {
                try await composition.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: asset, at: composition.duration)
            } catch {
                throw ArisConvertError("couldn't add \(source)", detail: error.localizedDescription)
            }
        }
        return composition
    }

    /// Runs async work on its own and waits for it, at most until `deadline` (then it is cancelled, and given a few
    /// seconds to stop).
    static func blocking<T>(until deadline: Date, timedOut: String = "it took too long, so Aris stopped (nothing was made)",
                            _ work: @escaping () async throws -> T) throws -> T {
        let box = ArisConvertBox<T>()
        let done = DispatchSemaphore(value: 0)
        let task = Task.detached {
            do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
            done.signal()
        }
        guard done.wait(timeout: .now() + max(0, deadline.timeIntervalSinceNow)) == .success, let result = box.result else {
            task.cancel()
            _ = done.wait(timeout: .now() + 5)
            throw ArisConvertError(timedOut)
        }
        return try result.get()
    }
}

/// A result handed from the async work to the waiting thread (the semaphore orders the two).
final class ArisConvertBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}
