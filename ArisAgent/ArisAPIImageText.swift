//
//  ArisAPIImageText.swift
//  aris-agent
//
//  The words in a turn's screen images, read on this Mac (Vision's text recognition, in memory, nothing written): what
//  an API brain whose model can't see gets instead of the images when no other installed brain can see them either
//  (ArisImageRouting.Route.readsText). Never a refusal: the feature degrades to the screen's text, which is outside text.
//

import CoreGraphics
import Foundation
import ImageIO
import Vision

enum ArisAPIImageText {
    /// The most text handed on, all images together.
    static let limit = 6_000

    /// Each image's label, then the lines read from it.
    static func text(of images: [ArisTurnImage], limit: Int = limit) -> String {
        let parts = images.map { image -> String in
            let lines = recognize(image.data)
            return "\(image.label):\n" + (lines.isEmpty ? "(읽을 수 있는 글자가 없어요)" : lines)
        }
        return String(parts.joined(separator: "\n\n").prefix(limit))
    }

    /// The text lines Vision finds in one encoded image, top to bottom; empty when none or the image can't be read.
    static func recognize(_ data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return "" }
        let observations = (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
