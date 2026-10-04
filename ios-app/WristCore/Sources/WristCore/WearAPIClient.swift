import Foundation

public struct WearAPIConfiguration: Sendable, Equatable {
    public var baseURL: URL
    public var token: String

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }
}

public enum WearAPIError: Error, Equatable, Sendable {
    case unauthorized
    case disabled
    case notFound
    case invalidURL
    case rateLimited(retryAfterSeconds: Int?)
    case server(status: Int, message: String?)
    case decoding(String)
    case transport(String)
}

public struct WearAPIClient: Sendable {
    private let configuration: WearAPIConfiguration
    private let transport: any HTTPTransport

    public init(configuration: WearAPIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    public func watches() async throws -> WatchesResponse {
        let url = try makeURL(path: "api/wear/watches")
        let response = try await perform(HTTPRequest(method: "GET", url: url, headers: baseHeaders()))
        try ensureSuccess(response)
        return try decode(WatchesResponse.self, from: response)
    }

    public func events(limit: Int = 50) async throws -> [WearEvent] {
        let url = try makeURL(path: "api/wear/events", query: [URLQueryItem(name: "limit", value: String(limit))])
        let response = try await perform(HTTPRequest(method: "GET", url: url, headers: baseHeaders()))
        try ensureSuccess(response)
        return try decode(EventsResponse.self, from: response).events
    }

    public func record(_ event: NewWearEvent) async throws -> RecordResponse {
        let url = try makeURL(path: "api/wear/events")
        var headers = baseHeaders()
        headers["Content-Type"] = "application/json"
        let body: Data
        do {
            body = try WristJSON.encoder.encode(event)
        } catch {
            throw WearAPIError.decoding(String(describing: error))
        }
        let response = try await perform(HTTPRequest(method: "POST", url: url, headers: headers, body: body))
        try ensureSuccess(response)
        return try decode(RecordResponse.self, from: response)
    }

    /// 204 -> true, 404 -> false (not thrown).
    public func delete(eventID: String) async throws -> Bool {
        let url = try makeURL(path: "api/wear/events", trailingSegment: eventID)
        let response = try await perform(HTTPRequest(method: "DELETE", url: url, headers: baseHeaders()))
        if response.statusCode == 404 { return false }
        try ensureSuccess(response)
        return true
    }

    // MARK: - Internals

    private func baseHeaders() -> [String: String] {
        [
            "Authorization": "Bearer \(configuration.token)",
            "Accept": "application/json",
        ]
    }

    private func makeURL(path: String, trailingSegment: String? = nil, query: [URLQueryItem]? = nil) throws -> URL {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw WearAPIError.invalidURL
        }
        var basePath = components.percentEncodedPath
        while basePath.hasSuffix("/") { basePath.removeLast() }
        var fullPath = basePath + "/" + path
        if let segment = trailingSegment {
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/")
            guard let encoded = segment.addingPercentEncoding(withAllowedCharacters: allowed), !encoded.isEmpty else {
                throw WearAPIError.invalidURL
            }
            fullPath += "/" + encoded
        }
        components.percentEncodedPath = fullPath
        components.queryItems = query
        guard let url = components.url else { throw WearAPIError.invalidURL }
        return url
    }

    private func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as WearAPIError {
            throw error
        } catch {
            throw WearAPIError.transport(String(describing: error))
        }
    }

    private func ensureSuccess(_ response: HTTPResponse) throws {
        let status = response.statusCode
        if (200..<300).contains(status) { return }
        switch status {
        case 401:
            throw WearAPIError.unauthorized
        case 503:
            throw WearAPIError.disabled
        case 404:
            throw WearAPIError.notFound
        case 429:
            let retry = response.header("Retry-After").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            throw WearAPIError.rateLimited(retryAfterSeconds: retry)
        default:
            let message = (try? WristJSON.decoder.decode(APIErrorBody.self, from: response.body))?.error
            throw WearAPIError.server(status: status, message: message)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        do {
            return try WristJSON.decoder.decode(type, from: response.body)
        } catch {
            throw WearAPIError.decoding(String(describing: error))
        }
    }
}
