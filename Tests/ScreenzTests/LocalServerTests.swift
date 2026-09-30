import XCTest
import Foundation
@testable import Screenz

final class LocalServerTests: XCTestCase {
    func testLocalPhotoUploadRoundTrip() async throws {
        let server = LocalServer()
        let received = expectation(description: "Received complete photo body")
        let photo = Data(repeating: 127, count: 200_000)
        server.handler = { request, reply in
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.path, "/test/upload")
            XCTAssertEqual(request.body, photo)
            reply(.json(["message": "received"]))
            received.fulfill()
        }
        defer { server.stop() }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            server.start { continuation.resume(with: $0) }
        }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/test/upload")!)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = photo
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        let value = try JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(value?["message"], "received")
        await fulfillment(of: [received], timeout: 5)
    }
}
