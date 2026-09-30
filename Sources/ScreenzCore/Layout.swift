import Foundation
import CoreGraphics

public struct Display: Identifiable, Equatable, Sendable {
    public let id: UInt32
    public let name: String
    public let width: Double
    public let height: Double
    public var x: Double
    public var y: Double
    public let isMain: Bool
    public var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    public var markerSize: Double { min(width, height) * 0.32 }

    public init(id: UInt32, name: String, width: Double, height: Double, x: Double, y: Double, isMain: Bool) {
        self.id = id; self.name = name; self.width = width; self.height = height
        self.x = x; self.y = y; self.isMain = isMain
    }
}

/// Coordinates in upright photo pixels, with the origin at the top left.
public struct Marker: Sendable {
    public let id: UInt32
    public let center: CGPoint
    public let size: Double
    public init(id: UInt32, center: CGPoint, size: Double) {
        self.id = id; self.center = center; self.size = size
    }
}

public enum LayoutError: LocalizedError {
    case missingMarkers, ambiguous, overlapping, disconnected, invalid
    public var errorDescription: String? {
        switch self {
        case .missingMarkers: return "Not every display marker was found. Step back, include all screens, and take another photo."
        case .ambiguous: return "The photo is too angled or the markers are too small. Take a straighter photo with all markers clearly visible."
        case .overlapping: return "Some displays overlap. Adjust their positions before applying."
        case .disconnected: return "Every display needs to touch another display. Adjust the positions so you can move the pointer between them."
        case .invalid: return "This display arrangement is not valid. Start again with the current displays."
        }
    }
}

public enum Layout {
    /// Connect nearest neighbors, preserving photo direction and snapping away physical bezels/gaps.
    /// This estimates a 2D arrangement; it does not reconstruct physical monitor geometry.
    public static func infer(displays: [Display], markers: [Marker]) throws -> [Display] {
        guard displays.count > 1, Set(displays.map(\.id)).count == displays.count,
              Set(markers.map(\.id)).count == markers.count,
              Set(displays.map(\.id)) == Set(markers.map(\.id)) else { throw LayoutError.missingMarkers }
        let observations = Dictionary(uniqueKeysWithValues: markers.map { ($0.id, $0) })
        guard markers.allSatisfy({ $0.size.isFinite && $0.size > 12 && $0.center.x.isFinite && $0.center.y.isFinite }) else { throw LayoutError.ambiguous }
        var result = displays
        let root = displays.firstIndex(where: \.isMain) ?? 0
        result[root].x = 0; result[root].y = 0
        var placed: Set<Int> = [root]
        while placed.count < displays.count {
            var best: (Int, Int, Double)?
            for i in placed.sorted() {
                for j in displays.indices where !placed.contains(j) {
                    let a = observations[displays[i].id]!, b = observations[displays[j].id]!
                    let distance = Double(hypot(b.center.x - a.center.x, b.center.y - a.center.y))
                    if best == nil || distance < best!.2 { best = (i, j, distance) }
                }
            }
            guard let (i, j, _) = best else { throw LayoutError.invalid }
            let a = observations[displays[i].id]!, b = observations[displays[j].id]!
            let scale = (a.size / displays[i].markerSize + b.size / displays[j].markerSize) / 2
            let dx = (b.center.x - a.center.x) / scale
            let dy = (b.center.y - a.center.y) / scale
            let anchor = result[i]
            var next = result[j]
            let horizontal = abs(dx) / ((anchor.width + next.width) / 2) >= abs(dy) / ((anchor.height + next.height) / 2)
            if horizontal {
                next.x = dx >= 0 ? anchor.x + anchor.width : anchor.x - next.width
                let offset = abs(dy) < min(anchor.height, next.height) * 0.12 ? 0 : dy
                next.y = (anchor.y + anchor.height / 2 + offset - next.height / 2).rounded()
                next.y = min(max(next.y, anchor.y - next.height + 40), anchor.y + anchor.height - 40)
            } else {
                next.y = dy >= 0 ? anchor.y + anchor.height : anchor.y - next.height
                let offset = abs(dx) < min(anchor.width, next.width) * 0.12 ? 0 : dx
                next.x = (anchor.x + anchor.width / 2 + offset - next.width / 2).rounded()
                next.x = min(max(next.x, anchor.x - next.width + 40), anchor.x + anchor.width - 40)
            }
            result[j] = next
            placed.insert(j)
        }
        return result
    }

    public static func validate(_ displays: [Display]) throws {
        guard !displays.isEmpty, Set(displays.map(\.id)).count == displays.count,
              displays.allSatisfy({ $0.width > 0 && $0.height > 0 && $0.x.isFinite && $0.y.isFinite && abs($0.x) < 100_000 && abs($0.y) < 100_000 }),
              let main = displays.first(where: \.isMain), main.x == 0, main.y == 0 else { throw LayoutError.invalid }
        for i in displays.indices {
            for j in displays.indices where j > i {
                let overlap = displays[i].rect.intersection(displays[j].rect)
                if !overlap.isNull && overlap.width > 0.5 && overlap.height > 0.5 { throw LayoutError.overlapping }
            }
        }
        var connected: Set<Int> = [0]
        var changed = true
        while changed {
            changed = false
            for i in connected.sorted() {
                for j in displays.indices where !connected.contains(j) {
                    let a = displays[i].rect, b = displays[j].rect
                    let verticalEdge = (abs(a.maxX - b.minX) < 1 || abs(b.maxX - a.minX) < 1) && min(a.maxY, b.maxY) - max(a.minY, b.minY) > 1
                    let horizontalEdge = (abs(a.maxY - b.minY) < 1 || abs(b.maxY - a.minY) < 1) && min(a.maxX, b.maxX) - max(a.minX, b.minX) > 1
                    if verticalEdge || horizontalEdge { connected.insert(j); changed = true }
                }
            }
        }
        guard connected.count == displays.count else { throw LayoutError.disconnected }
    }

    public static func snap(_ display: Display, to others: [Display], threshold: Double = 100) -> Display {
        var d = display
        let xs = others.flatMap { [$0.x, $0.x + $0.width, $0.x - d.width, $0.x + $0.width - d.width] }
        let ys = others.flatMap { [$0.y, $0.y + $0.height, $0.y - d.height, $0.y + $0.height - d.height] }
        if let x = xs.min(by: { abs($0 - d.x) < abs($1 - d.x) }), abs(x - d.x) < threshold { d.x = x }
        if let y = ys.min(by: { abs($0 - d.y) < abs($1 - d.y) }), abs(y - d.y) < threshold { d.y = y }
        d.x = d.x.rounded(); d.y = d.y.rounded()
        return d
    }
}
