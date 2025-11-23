import XCTest
@testable import HSBCPartnerSDKCore

final class ApiClientTests: XCTestCase {
    
    private func resolver() throws -> OpenAPIResolver {
        let json = """
        {
          "openapi": "3.0.0",
          "paths": {
            "/widgets": {
              "post": { "operationId": "createWidget" }
            }
          }
        }
        """
        return try OpenAPIResolver(openAPIData: Data(json.utf8))
    }
    
    func testResolveAndBuildRequest() throws {
        let resolver = try resolver()
        let baseURL = URL(string: "https://example.com/api")!
        
        let request = try resolver.makeRequest(
            baseURL: baseURL,
            operationId: "createWidget",
            body: ["name": "test"],
            headers: ["X-Test": "1"]
        )
        
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/widgets")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    
    func testCallRetriesOnServerErrors() async throws {
        let resolver = try resolver()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.reset(with: [
            .init(statusCode: 500, headers: [:], body: Data()),
            .init(statusCode: 429, headers: ["Retry-After": "0.0"], body: Data()),
            .init(statusCode: 200, headers: [:], body: Data("ok".utf8))
        ])
        
        let client = ApiClient(
            baseURL: URL(string: "https://example.com")!,
            resolver: resolver,
            pinningEnabled: false,
            session: session
        )
        
        let response = try await client.call(
            operationId: "createWidget",
            body: nil,
            headers: [:],
            idempotencyKey: "abc123"
        )
        
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(MockURLProtocol.requests.count, 3)
        let firstRequest = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertNotNil(firstRequest.value(forHTTPHeaderField: "traceparent"))
        XCTAssertEqual(firstRequest.value(forHTTPHeaderField: "X-Idempotency-Key"), "abc123")
    }
}

// MARK: - Mocks

final class MockURLProtocol: URLProtocol {
    struct QueuedResponse {
        let statusCode: Int
        let headers: [String: String]
        let body: Data?
    }
    
    static var queue: [QueuedResponse] = []
    static var requests: [URLRequest] = []
    
    static func reset(with responses: [QueuedResponse]) {
        queue = responses
        requests = []
    }
    
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    
    override func startLoading() {
        guard let response = MockURLProtocol.queue.first else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        MockURLProtocol.queue.removeFirst()
        MockURLProtocol.requests.append(request)
        
        guard let url = request.url,
              let httpResponse = HTTPURLResponse(url: url, statusCode: response.statusCode, httpVersion: nil, headerFields: response.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        if let body = response.body {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {}
}
