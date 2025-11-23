import Foundation
import HSBCPartnerSDKCore
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

public enum BiometricAuthError: Error {
    case notAvailable
    case userCancelled
    case scaRequired
    case unknown
}

/// Plugin that performs biometric authentication using LocalAuthentication.
#if canImport(LocalAuthentication)
@available(iOS 13.0, macOS 10.15, *)
public final class BiometricAuthPlugin: JourneyPlugin {
    public let name = "biometric_auth"
    
    public init() {}
    
    public func canHandle(_ method: String) -> Bool {
        method == "performBiometric"
    }
    
    public func handle(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        guard canHandle(method) else { throw BiometricAuthError.unknown }
        
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw BiometricAuthError.scaRequired
        }
        
        let reason = (params["reason"] as? String) ?? "Verify your identity"
        
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, evalError in
                if success {
                    continuation.resume(returning: ["biometric": "PASS"])
                } else if let evalError = evalError as? LAError {
                    switch evalError.code {
                    case .userCancel, .appCancel, .systemCancel:
                        continuation.resume(throwing: BiometricAuthError.userCancelled)
                    case .biometryLockout, .biometryNotAvailable, .biometryNotEnrolled:
                        continuation.resume(throwing: BiometricAuthError.scaRequired)
                    default:
                        continuation.resume(throwing: BiometricAuthError.unknown)
                    }
                } else {
                    continuation.resume(throwing: BiometricAuthError.unknown)
                }
            }
        }
    }
}
#else
public final class BiometricAuthPlugin: JourneyPlugin {
    public let name = "biometric_auth"
    public init() {}
    public func canHandle(_ method: String) -> Bool { method == "performBiometric" }
    public func handle(_ method: String, params: [String : Any]) async throws -> [String : Any] {
        throw BiometricAuthError.scaRequired
    }
}
#endif
