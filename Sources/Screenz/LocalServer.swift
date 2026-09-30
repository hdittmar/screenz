import Foundation
import Network
import Darwin
import ScreenzCore

final class LocalServer {
    struct Reply {
        let status: Int
        let type: String
        let body: Data
        static func json(_ value: [String: String]) -> Reply { json(200, value) }
        static func json(_ status: Int, _ value: [String: String]) -> Reply {
            Reply(status: status, type: "application/json", body: (try? JSONSerialization.data(withJSONObject: value)) ?? Data())
        }
    }
    private let queue = DispatchQueue(label: "screenz.server")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    var handler: ((HTTPRequest, @escaping (Reply) -> Void) -> Void)?

    func start(ready: @escaping (Result<UInt16, Error>) -> Void) {
        queue.async {
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                self.listener = listener
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready: if let port = listener.port { ready(.success(port.rawValue)) }
                    case .failed(let error): ready(.failure(error))
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak server = self] connection in server?.accept(connection) }
                listener.start(queue: self.queue)
            } catch { ready(.failure(error)) }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel(); self.listener = nil
            let active = self.connections.values
            self.connections.removeAll()
            active.forEach { $0.cancel() }
        }
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 8 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.connections.removeValue(forKey: id)?.cancel()
        }
        receive(connection, id: id, buffer: Data())
    }

    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self, self.connections[id] != nil else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            do {
                if let request = try HTTPRequest.parse(buffer) {
                    DispatchQueue.main.async {
                        guard let handler = self.handler else { self.send(.json(503, ["error": "Session ended"]), connection, id); return }
                        handler(request) { reply in self.send(reply, connection, id) }
                    }
                } else if complete || error != nil {
                    self.connections.removeValue(forKey: id)?.cancel()
                } else { self.receive(connection, id: id, buffer: buffer) }
            } catch {
                self.send(.json(400, ["error": "Invalid request or photo too large (maximum 24 MB)."]), connection, id)
            }
        }
    }

    private func send(_ reply: Reply, _ connection: NWConnection, _ id: UUID) {
        queue.async {
            guard self.connections[id] != nil else { return }
            let reason = reply.status == 200 ? "OK" : "Error"
            let header = "HTTP/1.1 \(reply.status) \(reason)\r\nContent-Type: \(reply.type)\r\nContent-Length: \(reply.body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src blob: data:; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'\r\n\r\n"
            var data = Data(header.utf8); data.append(reply.body)
            connection.send(content: data, completion: .contentProcessed { _ in
                self.connections.removeValue(forKey: id)?.cancel()
            })
        }
    }

    static func addresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [] }
        defer { freeifaddrs(list) }
        var results: [(String, String)] = []
        var pointer = list
        while let entry = pointer {
            defer { pointer = entry.pointee.ifa_next }
            let item = entry.pointee
            guard let address = item.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  item.ifa_flags & UInt32(IFF_UP) != 0, item.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: item.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                results.append((name, String(cString: host)))
            }
        }
        return results.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
