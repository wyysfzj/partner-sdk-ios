import Foundation

/// Errors emitted by ApiClient. Canonical mapping to SDK error codes can be added later.
public enum ApiClientError: Error {
    case unknownOperationId(String)
    case requestBuildFailed(Error)
    case transport(Error)
    case invalidResponse
    case retryLimitExceeded(status: Int, data: Data?, mapped: SdkErrorCode)
    case httpError(status: Int, data: Data?, mapped: SdkErrorCode)
}

@available(macOS 10.15, iOS 13.0, *)
public final class ApiClient {
    private let baseURL: URL
    private let resolver: OpenAPIResolver
    private let session: URLSession
    private let pinningEnabled: Bool
    private let maxAttempts = 3
    
    public init(
        baseURL: URL,
        resolver: OpenAPIResolver,
        pinningEnabled: Bool,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.resolver = resolver
        self.pinningEnabled = pinningEnabled
        if pinningEnabled {
            let config = URLSessionConfiguration.ephemeral
            self.session = URLSession(configuration: config, delegate: PinningDelegate(), delegateQueue: nil)
        } else {
            self.session = session
        }
    }
    
    /// Calls an API operation by operationId.
    /// - Parameters:
    ///   - operationId: OpenAPI operationId to invoke.
    ///   - body: Optional JSON body.
    ///   - headers: Additional headers.
    ///   - idempotencyKey: Optional idempotency key.
    public func call(
        operationId: String,
        body: [String: Any]?,
        headers: [String: String],
        idempotencyKey: String?
    ) async throws -> (status: Int, headers: [AnyHashable: Any], body: Data) {
        var attempt = 0
        var lastStatus: Int?
        var lastData: Data?
        
        while attempt < maxAttempts {
            var request: URLRequest
            do {
                guard let operation = resolver.resolve(operationId: operationId) else {
                    throw ApiClientError.unknownOperationId(operationId)
                }
                request = try OpenAPIResolver.buildRequest(
                    baseURL: baseURL,
                    operation: operation,
                    body: body,
                    headers: headers
                )
            } catch let error as OpenAPIResolverError {
                throw ApiClientError.requestBuildFailed(error)
            } catch {
                throw ApiClientError.requestBuildFailed(error)
            }
            
            request.setValue(newTraceparent(), forHTTPHeaderField: "traceparent")
            if let idempotencyKey, idempotencyKey.isEmpty == false {
                request.setValue(idempotencyKey, forHTTPHeaderField: "X-Idempotency-Key")
            }
            
            do {
                let (data, response) = try await data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ApiClientError.invalidResponse
                }
                
                let status = httpResponse.statusCode
                lastStatus = status
                lastData = data
                
                if shouldRetry(status: status), attempt < maxAttempts - 1 {
                    let delay = retryDelay(
                        attempt: attempt,
                        retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After")
                    )
                    try await sleep(seconds: delay)
                    attempt += 1
                    continue
                }
                
                if 200..<300 ~= status {
                    return (status, httpResponse.allHeaderFields, data)
                }
                
                let mapped = mapStatus(status, headers: httpResponse.allHeaderFields, data: data, idempotencyKey: idempotencyKey)
                if attempt == maxAttempts - 1 && shouldRetry(status: status) {
                    throw ApiClientError.retryLimitExceeded(
                        status: status,
                        data: data,
                        mapped: mapped
                    )
                } else {
                    throw ApiClientError.httpError(
                        status: status,
                        data: data,
                        mapped: mapped
                    )
                }
            } catch let error as ApiClientError {
                throw error
            } catch {
                if let urlError = error as? URLError, pinningEnabled, urlError.code == .serverCertificateUntrusted {
                    throw ApiClientError.httpError(status: -1, data: nil, mapped: .PINNING_FAIL)
                }
                throw ApiClientError.transport(error)
            }
        }
        
        throw ApiClientError.retryLimitExceeded(status: lastStatus ?? -1, data: lastData, mapped: .UNKNOWN)
    }
    
    private func shouldRetry(status: Int) -> Bool {
        status == 408 || status == 429 || (500...599).contains(status)
    }
    
    private func retryDelay(attempt: Int, retryAfter: String?) -> TimeInterval {
        if let retryAfter, let seconds = TimeInterval(retryAfter) {
            return seconds
        }
        
        let base = pow(2.0, Double(attempt)) * 0.5 // 0.5s, 1s, 2s
        let jitter = Double.random(in: 0...0.25)
        return base + jitter
    }
    
    private func sleep(seconds: TimeInterval) async throws {
        let nanos = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanos)
    }
    
    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if #available(macOS 12.0, iOS 15.0, *) {
            return try await session.data(for: request)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: ApiClientError.invalidResponse)
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }
    
    private func mapStatus(
        _ status: Int,
        headers: [AnyHashable: Any],
        data: Data,
        idempotencyKey: String?
    ) -> SdkErrorCode {
        switch status {
        case 401, 403:
            return .AUTH_EXPIRED
        case 408:
            return .NET_TIMEOUT
        case 409 where idempotencyKey != nil:
            return .IDEMPOTENT_REPLAY
        case 422, 400:
            return .VALIDATION_FAIL
        case 429:
            return .RATE_LIMITED
        default:
            return .UNKNOWN
        }
    }
}

private final class PinningDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        if #available(iOS 12.0, macOS 10.14, *) {
            var error: CFError?
            if SecTrustEvaluateWithError(serverTrust, &error) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
