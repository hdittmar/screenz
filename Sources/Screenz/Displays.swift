import AppKit
import CoreGraphics
import CoreImage
import Vision
import ImageIO
import ScreenzCore

enum DisplaySystem {
    static func read() -> [Display] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            let bounds = CGDisplayBounds(id)
            return Display(id: id, name: screen.localizedName, width: bounds.width, height: bounds.height,
                           x: bounds.minX, y: bounds.minY, isMain: id == CGMainDisplayID())
        }.sorted { $0.isMain && !$1.isMain }
    }

    static func ensureSameDisplays(_ expected: [Display]) throws {
        let actual = read()
        guard Set(actual.map(\.id)) == Set(expected.map(\.id)), expected.allSatisfy({ d in
            actual.contains { $0.id == d.id && $0.width == d.width && $0.height == d.height && $0.isMain == d.isMain }
        }) else { throw AppError.message("The connected displays or their resolution changed. Start a new scan.") }
        guard !actual.contains(where: { CGDisplayIsInMirrorSet($0.id) != 0 }) else {
            throw AppError.message("Turn off display mirroring in System Settings before arranging your screens.")
        }
    }

    static func apply(_ displays: [Display], permanently: Bool = false) throws {
        try ensureSameDisplays(displays)
        var config: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&config))
        var completed = false
        defer { if !completed { CGCancelDisplayConfiguration(config) } }
        for d in displays {
            try check(CGConfigureDisplayOrigin(config, d.id, Int32(d.x.rounded()), Int32(d.y.rounded())))
        }
        try check(CGCompleteDisplayConfiguration(config, permanently ? .permanently : .forAppOnly))
        completed = true
    }

    private static func check(_ error: CGError) throws {
        guard error == .success else { throw AppError.message("macOS could not change the display arrangement (error \(error.rawValue)).") }
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}

enum QR {
    static func image(_ value: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(value.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let raster = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cg = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(raster, from: raster.extent) else { return nil }
        return NSImage(cgImage: cg, size: raster.extent.size)
    }
}

enum PhotoDetector {
    static func detect(_ data: Data, session: String, displays: [Display]) throws -> [Marker] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue * height.doubleValue <= 100_000_000 else {
            throw AppError.message("This photo could not be read. Send a JPEG, PNG, or HEIC photo under 24 MB.")
        }
        // ImageIO normalizes EXIF rotation before Vision, including portrait phone photos.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: 4096]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AppError.message("The image could not be decoded. Try another photo.")
        }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image).perform([request])
        var found: [UInt32: Marker] = [:]
        for observation in request.results ?? [] {
            guard let text = observation.payloadStringValue else { continue }
            let parts = text.split(separator: ":")
            guard parts.count == 3, parts[0] == "screenz", parts[1] == session,
                  let id = UInt32(parts[2]), displays.contains(where: { $0.id == id }) else { continue }
            guard found[id] == nil else { throw AppError.message("A display marker appears twice. Take a photo without reflections or duplicate images.") }
            let w = Double(image.width), h = Double(image.height)
            func length(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(Double(a.x - b.x) * w, Double(a.y - b.y) * h) }
            let horizontal = (length(observation.topLeft, observation.topRight) + length(observation.bottomLeft, observation.bottomRight)) / 2
            let vertical = (length(observation.topLeft, observation.bottomLeft) + length(observation.topRight, observation.bottomRight)) / 2
            guard min(horizontal, vertical) / max(horizontal, vertical) > 0.45 else { throw LayoutError.ambiguous }
            let corners = [observation.topLeft, observation.topRight, observation.bottomLeft, observation.bottomRight]
            let centerX = Double(corners.reduce(CGFloat.zero) { $0 + $1.x }) / 4.0 * w
            let centerY = (1.0 - Double(corners.reduce(CGFloat.zero) { $0 + $1.y }) / 4.0) * h
            let center = CGPoint(x: centerX, y: centerY)
            found[id] = Marker(id: id, center: center, size: (horizontal + vertical) / 2)
        }
        guard found.count == displays.count else {
            throw AppError.message("Found \(found.count) of \(displays.count) displays. Include every marker, avoid glare, and take another photo.")
        }
        return Array(found.values)
    }
}

final class MarkerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    var onEscape: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

final class MarkerView: NSView {
    let display: Display
    let index: Int
    let qr: NSImage?
    init(display: Display, index: Int, session: String) {
        self.display = display; self.index = index
        qr = QR.image("screenz:\(session):\(display.id)")
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.15, alpha: 1).setFill()
        bounds.fill()
        let size = CGFloat(display.markerSize)
        let rect = CGRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: -24, dy: -24), xRadius: 12, yRadius: 12).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        qr?.draw(in: rect)
        func label(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let width = (text as NSString).size(withAttributes: attrs).width
            (text as NSString).draw(at: CGPoint(x: (bounds.width - width) / 2, y: y), withAttributes: attrs)
        }
        label("\(index + 1)  ·  \(display.name)", y: rect.maxY + 55, font: .systemFont(ofSize: 28, weight: .semibold), color: .white)
        label("Include every screen in one photo", y: rect.minY - 78, font: .systemFont(ofSize: 22), color: .white)
        label("SCREENZ     /     Press Esc to return", y: 38, font: .monospacedSystemFont(ofSize: 13, weight: .medium), color: .lightGray)
    }
}
