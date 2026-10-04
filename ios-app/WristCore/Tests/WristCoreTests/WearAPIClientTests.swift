import XCTest
@testable import WristCore

final class WearAPIClientTests: XCTestCase {
    private func makeClient(base: String = "https://example.test") -> (WearAPIClient, MockTransport) {
        let transport = MockTransport()
        let config = WearAPIConfiguration(baseURL: URL(string: base)!, token: "test-token")
        return (WearAPIClient(configuration: config, transport: transport), transport)
    }

    private func assertThrows(_ expected: WearAPIError, file: StaticString = #filePath, line: UInt = #line,
                              _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let e as WearAPIError {
            XCTAssertEqual(e, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }

    func testWatchesRequestShape() async throws {
        for base in ["https://example.test", "https://example.test/"] {
            let (client, transport) = makeClient(base: base)
            transport.enqueue(MockTransport.json(200, Fixtures.watchesResponse))
            let response = try await client.watches()
            XCTAssertEqual(response.watches.count, 3)
            let request = try XCTUnwrap(transport.recorded.first)
            XCTAssertEqual(request.method, "GET")
            XCTAssertEqual(request.url.absoluteString, "https://example.test/api/wear/watches")
            XCTAssertEqual(request.headers["Authorization"], "Bearer test-token")
            XCTAssertEqual(request.headers["Accept"], "application/json")
            XCTAssertNil(request.body)
        }
    }

    func testEventsLimitQuery() async throws {
        let (client, transport) = makeClient()
        transport.enqueue(MockTransport.json(200, #"{"events":[]}"#))
        let events = try await client.events(limit: 7)
        XCTAssertTrue(events.isEmpty)
        let request = try XCTUnwrap(transport.recorded.first)
        let components = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/api/wear/events")
        XCTAssertEqual(components.query, "limit=7")
    }

    func testRecordSendsBodyAndDecodesBothStatuses() async throws {
        let new = NewWearEvent(id: "11111111-1111-4111-8111-111111111111", watchId: "3m2uvdvq7622g",
                               wornAt: "2026-10-01T08:00:00-07:00", source: .app)
        let body = #"{"event":{"id":"11111111-1111-4111-8111-111111111111","watchId":"3m2uvdvq7622g","wornAt":"2026-10-01T08:00:00-07:00","source":"app","recordedAt":"2026-10-01T15:00:01.000Z"},"created":CREATED}"#
        for (status, created) in [(201, true), (200, false)] {
            let (client, transport) = makeClient()
            transport.enqueue(MockTransport.json(status, body.replacingOccurrences(of: "CREATED", with: created ? "true" : "false")))
            let response = try await client.record(new)
            XCTAssertEqual(response.created, created)
            XCTAssertEqual(response.event.id, new.id)
            XCTAssertEqual(response.event.recordedAt, "2026-10-01T15:00:01.000Z")

            let request = try XCTUnwrap(transport.recorded.first)
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.url.absoluteString, "https://example.test/api/wear/events")
            XCTAssertEqual(request.headers["Content-Type"], "application/json")
            XCTAssertEqual(request.headers["Authorization"], "Bearer test-token")
            let sent = try WristJSON.decoder.decode(NewWearEvent.self, from: try XCTUnwrap(request.body))
            XCTAssertEqual(sent, new)
        }
    }

    func testDelete() async throws {
        let (client, transport) = makeClient()
        transport.enqueue(HTTPResponse(statusCode: 204))
        transport.enqueue(MockTransport.json(404, #"{"error":"Not found"}"#))
        let first = try await client.delete(eventID: "abc-12345678")
        let second = try await client.delete(eventID: "abc-12345678")
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        let request = try XCTUnwrap(transport.recorded.first)
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.url.absoluteString, "https://example.test/api/wear/events/abc-12345678")

        transport.enqueue(MockTransport.json(401, #"{"error":"Unauthorized"}"#))
        await assertThrows(.unauthorized) { _ = try await client.delete(eventID: "abc-12345678") }
    }

    func testDeleteEncodesPathSegment() async throws {
        let (client, transport) = makeClient()
        transport.enqueue(HTTPResponse(statusCode: 204))
        _ = try await client.delete(eventID: "a/b c")
        let request = try XCTUnwrap(transport.recorded.first)
        XCTAssertEqual(request.url.absoluteString, "https://example.test/api/wear/events/a%2Fb%20c")
    }

    func testWatchesErrorMapping() async throws {
        let (client, transport) = makeClient()

        transport.enqueue(MockTransport.json(401, #"{"error":"Unauthorized"}"#))
        await assertThrows(.unauthorized) { _ = try await client.watches() }

        transport.enqueue(MockTransport.json(503, #"{"error":"Wear API disabled"}"#))
        await assertThrows(.disabled) { _ = try await client.watches() }

        transport.enqueue(MockTransport.json(429, #"{"error":"Too many requests."}"#, headers: ["Retry-After": "30"]))
        await assertThrows(.rateLimited(retryAfterSeconds: 30)) { _ = try await client.watches() }

        transport.enqueue(MockTransport.json(500, #"{"error":"boom"}"#))
        await assertThrows(.server(status: 500, message: "boom")) { _ = try await client.watches() }
    }

    func testDecodingFailure() async throws {
        let (client, transport) = makeClient()
        transport.enqueue(MockTransport.json(200, "not json"))
        do {
            _ = try await client.watches()
            XCTFail("expected decoding error")
        } catch let e as WearAPIError {
            if case .decoding = e {} else { XCTFail("wrong error \(e)") }
        }
    }

    func testTransportFailure() async throws {
        let (client, transport) = makeClient()
        transport.enqueue(.failure(MockTransportError(description: "offline")))
        do {
            _ = try await client.watches()
            XCTFail("expected transport error")
        } catch let e as WearAPIError {
            if case .transport(let message) = e {
                XCTAssertTrue(message.contains("offline"))
            } else {
                XCTFail("wrong error \(e)")
            }
        }
    }
}
