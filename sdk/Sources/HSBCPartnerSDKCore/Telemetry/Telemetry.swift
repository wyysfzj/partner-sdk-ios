import Foundation

/// Generates a W3C Trace Context traceparent string.
/// Format: 00-<trace-id>-<span-id>-01
/// Returns a 00-<trace>-<span>-01 string with random trace/span ids.
public func newTraceparent() -> String {
    let version = "00"
    let traceId = randomHexString(bytes: 16)
    let spanId = randomHexString(bytes: 8)
    let flags = "01"
    return "\(version)-\(traceId)-\(spanId)-\(flags)"
}

/// Executes a block within a named span, capturing timing information.
/// This is a no-op backend but captures timings for logs/events.
/// - Parameters:
///   - name: The name of the span.
///   - attributes: Attributes associated with the span. Keep payloads PII-free.
///   - block: The closure to execute.
public func withSpan(name: String, attributes: [String: Any], _ block: () -> Void) {
    let startTime = Date()
    block()
    let endTime = Date()
    let duration = endTime.timeIntervalSince(startTime)
    
    // Capture timings for logs/events
    // Note: In a real implementation, this would emit to a telemetry backend.
    print("Telemetry Span: \(name) | Duration: \(duration)s | Attributes: \(attributes)")
}

// MARK: - Private Helpers

private func randomHexString(bytes: Int) -> String {
    var data = Data(count: bytes)
    let result = data.withUnsafeMutableBytes {
        SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!)
    }
    if result == errSecSuccess {
        return data.map { String(format: "%02x", $0) }.joined()
    } else {
        // Fallback to simple random if SecRandomCopyBytes fails
        return (0..<bytes).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
