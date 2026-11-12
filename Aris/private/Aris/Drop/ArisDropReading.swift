//
//  ArisDropReading.swift
//  Aris
//
//  What the app finds out by opening a dropped file, on this Mac and nowhere else: whether a PDF has words in it (a
//  scan has none, so 요약 and 번역 are not offered for it), and the words in a picture (Vision's text recognition,
//  Korean and English, in memory, nothing written), which is what 글자 뽑기 sends. Never called for a file Aris holds
//  back from reading (ArisDropGuard).
//

import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Vision

enum ArisDropReading {
    /// How many of a PDF's first pages are looked at for words.
    static let pdfProbePages = 5
    /// A picture is read at most this big on its longer side (small print still reads; a 48-megapixel photo doesn't stall).
    static let pictureSide = 3_000
    /// A picture's words sent at most (ArisAttachmentText caps each file again).
    static let pictureText = 12_000

    /// Whether any of the PDF's first pages has words the app can send.
    static func pdfHasText(_ path: String) -> Bool {
        guard let pdf = PDFDocument(url: URL(fileURLWithPath: path)), !pdf.isLocked else { return false }
        return (0..<min(pdf.pageCount, pdfProbePages)).contains { index in
            pdf.page(at: index)?.string?.contains { !$0.isWhitespace } == true
        }
    }

    /// The lines Vision reads in the picture, top to bottom; empty when it has none or can't be opened. Slow enough
    /// (a few hundred milliseconds) that it is called off the main thread.
    static func pictureWords(_ path: String) -> String {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: pictureSide]
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) } catch { return "" }
        let lines = (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }.compactMap { $0.topCandidates(1).first?.string }
        return String(lines.joined(separator: "\n").prefix(pictureText))
    }
}
