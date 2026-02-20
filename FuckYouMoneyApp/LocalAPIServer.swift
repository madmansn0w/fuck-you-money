import Foundation
import Network

/// Minimal local HTTP API server for FuckYouMoney (localhost only).
/// Handles: GET /v1/health, GET /v1/portfolio, POST /v1/trades, POST /v1/refresh.
final class LocalAPIServer: @unchecked Sendable {
    private let port: UInt16
    private let handler: (APIRequest) async -> APIResponse
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "LocalAPIServer")

    struct APIRequest {
        let method: String
        let path: String
        let query: [String: String]
        let body: Data?
    }

    struct APIResponse {
        let statusCode: Int
        let body: Data?
        let contentType: String?

        static func json(_ data: Data, status: Int = 200) -> APIResponse {
            APIResponse(statusCode: status, body: data, contentType: "application/json")
        }
        static func empty(status: Int = 204) -> APIResponse {
            APIResponse(statusCode: status, body: nil, contentType: nil)
        }
    }

    init(port: UInt16, handler: @escaping (APIRequest) async -> APIResponse) {
        self.port = port
        self.handler = handler
    }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            l.stateUpdateHandler = { state in
                if case .failed(let error) = state { print("LocalAPIServer listener failed: \(error)") }
            }
            l.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }
            l.start(queue: queue)
            listener = l
        } catch {
            print("LocalAPIServer failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections = []
    }

    private func accept(_ conn: NWConnection) {
        connections.append(conn)
        conn.start(queue: queue)
        readRequest(conn)
    }

    private func readRequest(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if error != nil {
                self.remove(conn); return
            }
            guard let data = data, !data.isEmpty else {
                if isComplete { self.remove(conn) }; return
            }
            self.handleRequest(data: data, conn: conn)
        }
    }

    private func handleRequest(data: Data, conn: NWConnection) {
        guard let request = parseRequest(data) else {
            sendResponse(conn, .empty(status: 400)); return
        }
        Task {
            let response = await handler(request)
            await MainActor.run {
                logAPIRequest(method: request.method, path: request.path, status: response.statusCode)
                sendResponse(conn, response)
            }
        }
    }

    private func sendResponse(_ conn: NWConnection, _ response: APIResponse) {
        let statusLine = "HTTP/1.1 \(response.statusCode) \(statusText(response.statusCode))\r\n"
        var headers = "Content-Length: \(response.body?.count ?? 0)\r\n"
        if let ct = response.contentType { headers += "Content-Type: \(ct)\r\n" }
        headers += "Connection: close\r\n\r\n"
        var payload = (statusLine + headers).data(using: .utf8)!
        if let body = response.body { payload.append(body) }
        conn.send(content: payload, completion: .contentProcessed { [weak self] _ in
            conn.cancel()
            self?.remove(conn)
        })
    }

    private func remove(_ conn: NWConnection) {
        connections.removeAll { $0 === conn }
    }

    /// Logs API request for debugging: method, path, status code.
    private func logAPIRequest(method: String, path: String, status: Int) {
        print("[API] \(method) \(path) \(status)")
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }

    private func parseRequest(_ data: Data) -> APIRequest? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let lines = raw.components(separatedBy: "\r\n")
        guard let first = lines.first, let space1 = first.firstIndex(of: " "), let space2 = first[first.index(after: space1)...].firstIndex(of: " ") else { return nil }
        let method = String(first[..<space1])
        let pathQuery = String(first[first.index(after: space1)..<space2])
        let path: String
        let query: [String: String]
        if let q = pathQuery.firstIndex(of: "?") {
            path = String(pathQuery[..<q])
            query = parseQuery(String(pathQuery[pathQuery.index(after: q)...]))
        } else {
            path = pathQuery
            query = [:]
        }
        var body: Data?
        if let idx = lines.firstIndex(where: { $0.isEmpty }), idx + 1 < lines.count {
            let bodyStart = lines[..<idx].joined(separator: "\r\n").count + 2
            if bodyStart < data.count { body = data.subdata(in: bodyStart..<data.count) }
        }
        return APIRequest(method: method, path: path, query: query, body: body)
    }

    private func parseQuery(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for part in s.components(separatedBy: "&") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, let key = pair[0].removingPercentEncoding, let val = pair[1].removingPercentEncoding {
                out[key] = val
            }
        }
        return out
    }
}
