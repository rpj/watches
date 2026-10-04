import Foundation
@testable import WristCore

struct MockTransportError: Error, CustomStringConvertible {
    let description: String
}

final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _recorded: [HTTPRequest] = []
    private var _responses: [Result<HTTPResponse, Error>] = []

    var recorded: [HTTPRequest] {
        lock.lock(); defer { lock.unlock() }
        return _recorded
    }

    var responses: [Result<HTTPResponse, Error>] {
        lock.lock(); defer { lock.unlock() }
        return _responses
    }

    func enqueue(_ result: Result<HTTPResponse, Error>) {
        lock.lock(); defer { lock.unlock() }
        _responses.append(result)
    }

    func enqueue(_ response: HTTPResponse) {
        enqueue(.success(response))
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let next: Result<HTTPResponse, Error>? = {
            lock.lock(); defer { lock.unlock() }
            _recorded.append(request)
            return _responses.isEmpty ? nil : _responses.removeFirst()
        }()
        guard let next else {
            throw MockTransportError(description: "MockTransport: no queued response for \(request.method) \(request.url)")
        }
        return try next.get()
    }

    static func json(_ status: Int, _ body: String, headers: [String: String] = [:]) -> HTTPResponse {
        var all = headers
        if all["Content-Type"] == nil { all["Content-Type"] = "application/json" }
        return HTTPResponse(statusCode: status, headers: all, body: Data(body.utf8))
    }
}
