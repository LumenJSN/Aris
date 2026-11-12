//
//  ArisConvertPDF.swift
//  aris-tools
//
//  PDFs for `merge`, `split` and `convert`, with PDFKit and CoreGraphics only: PDFs and pictures merged into one PDF,
//  one PDF split by pages or ranges, and pages drawn as pictures. Adapted from the user's Lime (MIT, Tools/PDFTools.swift).
//

import AppKit
import CoreGraphics
import Foundation
import PDFKit

enum ArisConvertPDF {
    /// The most pages one call writes out (split, or pages as pictures).
    static let mostPages = 500
    /// Pages drawn as pictures at this many pixels per inch unless a size is given.
    static let pageDPI: Double = 144

    static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ArisConvertError("it isn't a PDF Aris can read")
        }
        guard !document.isLocked else { throw ArisConvertError("it is locked with a password") }
        return document
    }

    /// "1-3,5" as groups of page indexes (from 0) inside `count`; nil when it isn't that shape or names a page that
    /// isn't there.
    static func ranges(_ text: String, count: Int) -> [[Int]]? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty, parts.count <= 200 else { return nil }
        var groups: [[Int]] = []
        for part in parts {
            let ends = part.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            guard (1...2).contains(ends.count), ends.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
                  let first = Int(ends[0]), let last = Int(ends[ends.count - 1]), first >= 1, first <= last, last <= count else { return nil }
            groups.append(Array((first - 1)...(last - 1)))
        }
        return groups
    }

    /// A group's name in a file: "3" or "1-3".
    static func label(_ group: [Int]) -> String {
        group.count == 1 ? "\(group[0] + 1)" : "\(group[0] + 1)-\(group[group.count - 1] + 1)"
    }

    /// PDFs and pictures, in order, as one PDF. `labels`: what a failure calls each file.
    /// `most`: pages in the merged PDF at most.
    static func merge(_ sources: [URL], kinds: [ArisConvert.Kind], labels: [String], most: Int = mostPages, to url: URL) throws {
        let merged = PDFDocument()
        for ((source, kind), label) in zip(zip(sources, kinds), labels) {
            do {
                if kind == .pdf {
                    let document = try open(source)
                    guard merged.pageCount + document.pageCount <= most else { throw ArisConvertError("that's more than \(most) pages in one PDF") }
                    for index in 0..<document.pageCount {
                        try autoreleasepool {
                            guard let page = document.page(at: index)?.copy() as? PDFPage else { throw ArisConvertError("page \(index + 1) is unreadable") }
                            merged.insert(page, at: merged.pageCount)
                        }
                    }
                } else {
                    guard merged.pageCount < most else { throw ArisConvertError("that's more than \(most) pages in one PDF") }
                    try autoreleasepool { merged.insert(try picturePage(source), at: merged.pageCount) }
                }
            } catch let problem as ArisConvertError {
                throw ArisConvertError("\(label): \(problem.message)", detail: problem.detail)
            }
        }
        guard merged.write(to: url) else { throw ArisConvertError("couldn't write the merged PDF") }
    }

    /// One picture as a PDF page, its size at its own pixels per inch.
    private static func picturePage(_ source: URL) throws -> PDFPage {
        let image = try ArisConvertImages.load(source)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let pdf = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw ArisConvertError("couldn't make a page of it")
        }
        let dpi = ArisConvertImages.dpi(source)
        var box = CGRect(x: 0, y: 0, width: Double(image.width) * 72 / dpi, height: Double(image.height) * 72 / dpi)
        pdf.beginPage(mediaBox: &box)
        pdf.draw(image, in: box)
        pdf.endPage()
        pdf.closePDF()
        guard let page = PDFDocument(data: data as Data)?.page(at: 0) else { throw ArisConvertError("couldn't make a page of it") }
        return page
    }

    /// The pages of `group` as their own PDF.
    static func extract(_ document: PDFDocument, pages group: [Int], to url: URL) throws {
        let single = PDFDocument()
        for index in group {
            guard let page = document.page(at: index)?.copy() as? PDFPage else { throw ArisConvertError("page \(index + 1) is unreadable") }
            single.insert(page, at: single.pageCount)
        }
        guard single.write(to: url) else { throw ArisConvertError("couldn't write pages \(label(group))") }
    }

    /// One page drawn as a picture: at pageDPI, or `maxSide` on its longer side, or `percent` of its pageDPI size.
    static func pageImage(_ page: PDFPage, maxSide: Int?, percent: Int?) throws -> CGImage {
        let bounds = page.bounds(for: .cropBox)
        let turned = page.rotation % 180 != 0
        let size = turned ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        var scale = pageDPI / 72
        if let maxSide { scale = Double(maxSide) / max(size.width, size.height, 1) }
        if let percent { scale *= Double(percent) / 100 }
        let width = max(1, Int((size.width * scale).rounded())), height = max(1, Int((size.height * scale).rounded()))
        guard let context = ArisConvertImages.context(width: width, height: height, opaque: true) else {
            throw ArisConvertError("that page is too large to draw")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        guard let image = context.makeImage() else { throw ArisConvertError("couldn't draw that page") }
        return image
    }
}
