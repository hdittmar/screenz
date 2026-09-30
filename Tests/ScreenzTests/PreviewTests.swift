import XCTest
import SwiftUI
import AppKit
@testable import Screenz

final class PreviewTests: XCTestCase {
    @MainActor
    func testRenderWelcomeAndArrangement() throws {
        guard let directory = ProcessInfo.processInfo.environment["SCREENZ_PREVIEW_DIR"] else { return }
        let model = AppModel()
        model.demo()
        model.displays = model.proposal
        model.proposal = []; model.isDemo = false; model.phase = .idle
        for state in ["welcome", "pairing", "arrangement", "dark"] {
            if state == "pairing" {
                model.phase = .pairing
                model.url = "http://192.168.1.2:8080/s/0123456789abcdef0123456789abcdef"
                model.status = "Scan the code with your iPhone camera."
                XCTAssertNotNil(QR.image(model.url))
            }
            if state == "arrangement" { model.demo() }
            let renderer = ImageRenderer(content: MainView(model: model)
                .frame(width: 780, height: 570).environment(\.colorScheme, state == "dark" ? .dark : .light))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(state).png"))
        }
    }
}
