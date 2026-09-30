import XCTest
@testable import ScreenzCore

final class HTTPRequestTests: XCTestCase {
    func testFragmentedUploadWaitsForBody() throws {
        let header = "POST /s/token/upload HTTP/1.1\r\nHost: 192.168.1.2:8080\r\nContent-Length: 5\r\nContent-Type: image/jpeg\r\n\r\n"
        XCTAssertNil(try HTTPRequest.parse(Data((header + "ab").utf8)))
        let result = try XCTUnwrap(HTTPRequest.parse(Data((header + "abcde").utf8)))
        XCTAssertEqual(result.method, "POST")
        XCTAssertEqual(result.body, Data("abcde".utf8))
        XCTAssertEqual(result.headers["content-type"], "image/jpeg")
    }
    func testGetWithoutBody() throws {
        let result = try XCTUnwrap(HTTPRequest.parse(Data("GET /s/token HTTP/1.1\r\nHost: local\r\n\r\n".utf8)))
        XCTAssertEqual(result.path, "/s/token")
        XCTAssertTrue(result.body.isEmpty)
    }
    func testRequestSmugglingAndNegativeLengthsRejected() {
        for headers in ["Content-Length: 2\r\nContent-Length: 3", "Content-Length: -1", "Content-Length: +2", "Transfer-Encoding: chunked", "Content-Length: 9999999999"] {
            XCTAssertThrowsError(try HTTPRequest.parse(Data("POST / HTTP/1.1\r\n\(headers)\r\n\r\n".utf8)))
        }
    }
    func testHeaderBoundAndMalformedLine() {
        XCTAssertThrowsError(try HTTPRequest.parse(Data(repeating: 65, count: 16_385)))
        XCTAssertThrowsError(try HTTPRequest.parse(Data("GET / HTTP/1.1\r\nBroken header\r\n\r\n".utf8)))
    }
}
