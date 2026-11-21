//
//  ArisAppsLayout.swift
//  Shared/Core/Apps
//
//  Where window.move puts a window ("left" half, a corner, the center, x,y, the next display) and how window.tile lays
//  several out, in global points with the origin top left (Accessibility's coordinates). Whole points, inside the
//  display's usable area. Pure (its own rectangle, so Shared/Core stays Foundation only).
//

import Foundation

extension ArisApps {
    struct Rect: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var maxX: Double { x + width }
        var maxY: Double { y + height }
        var midX: Double { x + width / 2 }
        var midY: Double { y + height / 2 }

        /// The area two rectangles share (0 when they don't meet).
        func overlap(_ other: Rect) -> Double {
            let w = min(maxX, other.maxX) - max(x, other.x), h = min(maxY, other.maxY) - max(y, other.y)
            return w > 0 && h > 0 ? w * h : 0
        }
    }

    enum Layout {
        static let positions = ["left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right", "center", "full", "next-display"]

        /// The display a window is on: the one it overlaps most, else the first.
        static func display(of window: Rect, in displays: [Rect]) -> Rect? {
            let best = displays.max { $0.overlap(window) < $1.overlap(window) }
            return best.flatMap { $0.overlap(window) > 0 ? $0 : nil } ?? displays.first
        }

        /// The frame for a named place (or "x,y", keeping the size), nil for words it doesn't know.
        static func frame(_ place: String, window: Rect, displays: [Rect]) -> Rect? {
            guard let area = display(of: window, in: displays) else { return nil }
            let x = area.x.rounded(.up), y = area.y.rounded(.up)
            let fullWidth = area.width.rounded(.down), fullHeight = area.height.rounded(.down)
            let halfWidth = (area.width / 2).rounded(.down), halfHeight = (area.height / 2).rounded(.down)
            switch place.lowercased().replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "-") {
            case "left", "왼쪽": return Rect(x: x, y: y, width: halfWidth, height: fullHeight)
            case "right", "오른쪽": return Rect(x: x + halfWidth, y: y, width: halfWidth, height: fullHeight)
            case "top", "위": return Rect(x: x, y: y, width: fullWidth, height: halfHeight)
            case "bottom", "아래": return Rect(x: x, y: y + halfHeight, width: fullWidth, height: halfHeight)
            case "top-left": return Rect(x: x, y: y, width: halfWidth, height: halfHeight)
            case "top-right": return Rect(x: x + halfWidth, y: y, width: halfWidth, height: halfHeight)
            case "bottom-left": return Rect(x: x, y: y + halfHeight, width: halfWidth, height: halfHeight)
            case "bottom-right": return Rect(x: x + halfWidth, y: y + halfHeight, width: halfWidth, height: halfHeight)
            case "full", "maximize", "전체": return Rect(x: x, y: y, width: fullWidth, height: fullHeight)
            case "center", "가운데":
                let width = min(window.width, area.width), height = min(window.height, area.height)
                return Rect(x: (area.midX - width / 2).rounded(), y: (area.midY - height / 2).rounded(), width: width, height: height)
            case "next-display", "다음-화면":
                guard displays.count > 1, let index = displays.firstIndex(of: area) else { return nil }
                let next = displays[(index + 1) % displays.count]
                let width = min(window.width, next.width), height = min(window.height, next.height)
                let dx = (window.x - area.x) / max(1, area.width), dy = (window.y - area.y) / max(1, area.height)
                let left = min(next.maxX - width, next.x + dx * next.width), top = min(next.maxY - height, next.y + dy * next.height)
                return Rect(x: left.rounded(), y: top.rounded(), width: width, height: height)
            default:
                let parts = place.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard parts.count == 2 else { return nil }
                return Rect(x: parts[0], y: parts[1], width: window.width, height: window.height)
            }
        }

        /// One frame per window in reading order: `grid` "RxC", else side by side up to three, then rows of three.
        static func tile(count: Int, grid: String?, in area: Rect) -> [Rect] {
            guard count > 0 else { return [] }
            var rows = 1, columns = count
            if let grid {
                let parts = grid.lowercased().split(separator: "x").compactMap { Int($0) }
                if parts.count == 2, parts[0] > 0, parts[1] > 0, parts[0] * parts[1] <= 16 { rows = parts[0]; columns = parts[1] }
            } else if count == 4 {
                rows = 2
                columns = 2
            } else if count > 3 {
                columns = 3
                rows = min(3, (count + 2) / 3)
            }
            let width = (area.width / Double(columns)).rounded(.down), height = (area.height / Double(rows)).rounded(.down)
            let left = area.x.rounded(.up), top = area.y.rounded(.up)
            return (0..<min(count, rows * columns)).map { index in
                Rect(x: left + Double(index % columns) * width, y: top + Double(index / columns) * height, width: width, height: height)
            }
        }
    }
}
