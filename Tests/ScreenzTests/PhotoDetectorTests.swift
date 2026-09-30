import XCTest
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import ScreenzCore
@testable import Screenz

final class PhotoDetectorTests: XCTestCase {
    let session = "0123456789abcdef0123456789abcdef"
    var displays: [Display] {
        [Display(id: 1, name: "Left", width: 1000, height: 800, x: 0, y: 0, isMain: true),
         Display(id: 2, name: "Right", width: 1000, height: 800, x: 1000, y: 0, isMain: false)]
    }
    func photo(orientation: Int = 1) throws -> Data {
        var canvas = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 1800, height: 900))
        for (index, display) in displays.enumerated() {
            let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
            filter.setValue(Data("screenz:\(session):\(display.id)".utf8), forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            let qr = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
            let positioned = qr.transformed(by: CGAffineTransform(translationX: CGFloat(200 + index * 900), y: 300))
            canvas = positioned.composited(over: canvas)
        }
        let cg = try XCTUnwrap(CIContext(options: [.useSoftwareRenderer: true]).createCGImage(canvas, from: canvas.extent))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cg, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
    func testRealVisionDetectsMultipleSessionMarkers() throws {
        let markers = try PhotoDetector.detect(photo(), session: session, displays: displays)
        XCTAssertEqual(Set(markers.map(\.id)), [1, 2])
        let result = try Layout.infer(displays: displays, markers: markers)
        XCTAssertEqual(result[1].x, 1000)
        XCTAssertEqual(result[1].y, 0)
    }
    func testEXIFRotationIsApplied() throws {
        let markers = try PhotoDetector.detect(photo(orientation: 6), session: session, displays: displays)
        let a = try XCTUnwrap(markers.first { $0.id == 1 }), b = try XCTUnwrap(markers.first { $0.id == 2 })
        XCTAssertLessThan(abs(a.center.x - b.center.x), 5)
        XCTAssertGreaterThan(b.center.y, a.center.y)
    }
    func testOldSessionAndInvalidImageAreRejected() throws {
        XCTAssertThrowsError(try PhotoDetector.detect(photo(), session: "expired", displays: displays))
        XCTAssertThrowsError(try PhotoDetector.detect(Data("not an image".utf8), session: session, displays: displays))
    }
}
