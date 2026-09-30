import Foundation

/// A bounded, single-request HTTP/1.1 parser. The phone sends a Blob with Content-Length.
public struct HTTPRequest {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data
    public static let maxBody = 24 * 1024 * 1024
    public enum ParseError: Error { case malformed, tooLarge }

    public static func parse(_ data: Data) throws -> HTTPRequest? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > 16_384 { throw ParseError.tooLarge }
            return nil
        }
        guard separator.lowerBound <= 16_384,
              let head = String(data: data[..<separator.lowerBound], encoding: .utf8) else { throw ParseError.malformed }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count == 3, first[2] == "HTTP/1.1" || first[2] == "HTTP/1.0", first[1].hasPrefix("/") else { throw ParseError.malformed }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { throw ParseError.malformed }
            let key = line[..<colon].lowercased()
            guard headers[key] == nil else { throw ParseError.malformed }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil else { throw ParseError.malformed }
        let length: Int
        if let value = headers["content-length"] {
            guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }), let parsed = Int(value) else { throw ParseError.malformed }
            length = parsed
        } else { length = 0 }
        guard length <= maxBody else { throw ParseError.tooLarge }
        guard data.count >= separator.upperBound + length else { return nil }
        return HTTPRequest(method: String(first[0]), path: String(first[1]), headers: headers,
                           body: Data(data[separator.upperBound..<(separator.upperBound + length)]))
    }
}
