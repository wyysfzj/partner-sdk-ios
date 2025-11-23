# Third-Party Integration Guide: HSBC Journey-Agnostic iOS SDK

## 1. Prerequisites
- Xcode 15+ on macOS; iOS deployment target 14+.
- Access to HSBC-provided journey manifests, OpenAPI endpoints, and context tokens.
- Custom URL scheme registered in your app for OIDC redirect (e.g., `ctrip://`).

## 2. Add the SDK
### Via Swift Package (source)
1. In Xcode: File → Add Packages… → enter your repo URL/path.
2. Select `HSBCPartnerSDK` package; add products `HSBCPartnerSDKCore` (required) and `HSBCPlugins` (optional plugins like biometrics).

### Via XCFramework (binary)
1. Obtain `HSBCPartnerSDKCore.xcframework` (from HSBC release).
2. Drag into your Xcode project, ensure “Copy items if needed” checked, link to your app target.

## 3. Configure ATS / App Bound Domains
- Add HSBC host domains to `NSAppTransportSecurity` exceptions if needed (prefer full ATS compliance).
- For WKWebView isolation, configure `WKAppBoundDomains` to include HSBC web host domains used by the journeys.

## 4. Initialize the SDK
```swift
import HSBCPartnerSDKCore

let config = HSBCInitConfig(
    environment: .sandbox,              // or .production
    partnerId: "your-partner-id",
    clientId: "your-client-id",
    redirectScheme: "yourapp",          // must be handled by your app
    locale: Locale(identifier: "en_US"),
    remoteConfigURL: URL(string: "https://.../remote-config"), // optional
    featureFlags: [:],
    telemetryOptIn: true
)
HSBCPartnerSdk.initialize(config: config)

HSBCPartnerSdk.setEventListener { name, attrs in
    print("HSBC SDK Event: \(name) -> \(attrs)")
}
```

## 5. Start a Journey
```swift
let params = JourneyStartParams(
    journeyId: "money_transfer",     // provided by HSBC
    contextToken: "<context-token>", // server-issued, short-lived
    resumeToken: nil
)

HSBCPartnerSdk.startJourney(
    from: yourViewController,        // presenter for UI
    params: params
) { result in
    switch result {
    case .completed(let payload):
        // handle success
    case .pending(let payload):
        // handle pending state
    case .cancelled:
        // handle user cancel
    case .failed(let code, let message, let recoverable):
        // present error; retry if recoverable
    }
}
```

## 6. Plugins (Optional)
- The SDK includes a biometric plugin in `HSBCPlugins`. Register if needed:
```swift
import HSBCPlugins
PluginRegistry.shared.register(BiometricAuthPlugin())
```

## 7. Resume Flows
- If HSBC allows resume, you may receive a `resumeToken`. Pass it in `JourneyStartParams` next time. The SDK handles PII-free snapshots internally.

## 8. Testing
- Sandbox: Use HSBC-provided sandbox manifests/context tokens.
- Unit/UI tests: Exercise journey start and verify result handling. If using WKWebView, add App Bound Domains and ATS exceptions as required.

## 9. Error Handling
- `JourneyResult.failed` includes `code` (e.g., `AUTH_EXPIRED`, `RATE_LIMITED`, `NET_TIMEOUT`), `message`, and `recoverable`. Treat recoverable errors with retry/refresh flows; fatal errors should surface a user-facing message and allow exit.

## 10. Security Tips
- Keep context tokens short-lived and server-issued.
- Ensure ATS/AppBoundDomains configured for HSBC hosts.
- Do not log PII; handle SDK events as privacy-safe telemetry.

## 11. Updating
- The SDK is semver’d. Update via SwiftPM or replace the XCFramework when HSBC publishes a new release.

## 12. Support
- For access to manifests/OpenAPI/context tokens and production onboarding, contact your HSBC integration manager. For technical issues, provide SDK version, journeyId, and logs (omitting PII). 
