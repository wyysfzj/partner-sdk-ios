import Foundation

/// Returns true when the given origin matches an allowed origin list (scheme + host).
/// Only HTTPS is permitted unless allowFileOrigins is explicitly enabled for dev scenarios.
public func isAllowed(origin: URL, allowed: [URL], allowFileOrigins: Bool = false) -> Bool {
    if allowFileOrigins, origin.isFileURL {
        return true
    }
    guard let scheme = origin.scheme?.lowercased(),
          let host = origin.host?.lowercased(),
          scheme == "https" else {
        return false
    }
    
    return allowed.contains { candidate in
        guard let cScheme = candidate.scheme?.lowercased(),
              let cHost = candidate.host?.lowercased(),
              cScheme == "https" else {
            return false
        }
        return host == cHost
    }
}

// Production relies on ATS (TLS 1.2+) and WKAppBoundDomains listing HSBC domains for web content isolation.
// Development may allow file:// behind a dedicated feature flag and must never be enabled for production builds.
