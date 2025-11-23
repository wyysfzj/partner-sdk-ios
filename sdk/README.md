# HSBC Journey-Agnostic iOS SDK

An iOS SDK that lets partners embed HSBC journeys (e.g., Account Opening, Money Transfer) using signed manifests and OpenAPI bundles. The SDK provides a stable public API, a secure hybrid container, a JS bridge, and a runtime engine that interprets manifests to drive flows without code changes per journey.

## Features
- Public API to initialize and start journeys (`HSBCPartnerSdk`).
- Manifest-driven runtime (state machine, bindings, guard expressions, timeouts).
- Secure web container (ASWebAuthenticationSession, WKWebView with origin enforcement).
- JS bridge v1.1 with handshake, per-step allow-list, signed envelopes, plugin dispatch.
- ApiClient with retries/backoff, traceparent, idempotency header, error mapping to `SdkErrorCode`.
- Session snapshots (Keychain) for resume (PII-free).
- Example SwiftUI demo app.
- CI workflow to build/test and produce an XCFramework.

## Getting Started
1. **Add the SDK**
   - SwiftPM: Add the repo URL in Xcode (File → Add Packages…) and select `HSBCPartnerSDKCore` (+ `HSBCPlugins` if needed).
   - XCFramework: Use the `dist/HSBCPartnerSDKCore.xcframework` from releases and link it to your app target.

2. **Initialize**
   ```swift
   import HSBCPartnerSDKCore
   let config = HSBCInitConfig(
       environment: .sandbox,
       partnerId: "your-partner-id",
       clientId: "your-client-id",
       redirectScheme: "yourapp",
       locale: Locale(identifier: "en_US"),
       remoteConfigURL: URL(string: "https://..."), // optional
       featureFlags: [:],
       telemetryOptIn: true
   )
   HSBCPartnerSdk.initialize(config: config)
   HSBCPartnerSdk.setEventListener { name, attrs in print("HSBC SDK Event: \(name) -> \(attrs)") }
   ```

3. **Start a Journey**
   ```swift
   let params = JourneyStartParams(
       journeyId: "money_transfer",
       contextToken: "<context-token>"
   )
   HSBCPartnerSdk.startJourney(from: presenterVC, params: params) { result in
       switch result {
       case .completed(let payload): print("Completed", payload)
       case .pending(let payload): print("Pending", payload)
       case .cancelled: print("Cancelled")
       case .failed(let code, let message, let recoverable): print("Failed", code, message, recoverable)
       }
   }
   ```

## Project Structure
- `Sources/HSBCPartnerSDKCore`: Core SDK (public API, runtime, manifest loader/models, OpenAPI resolver, ApiClient, container, bridge, security).
- `Sources/HSBCPlugins`: Optional plugins (e.g., BiometricAuth, JourneyPlugin protocol, PluginRegistry).
- `Tests/HSBCPartnerSDKCoreTests`: Unit tests (manifest, bridge handshake, state machine, ApiClient, session, OpenAPI resolver).
- `examples/PartnerDemoApp`: SwiftUI demo app + UITest target.
- `docs/`: Design docs and guides.
- `.github/workflows/ios-sdk.yml`: CI build/test/publish pipeline.

## Demo App
The demo lives in `examples/PartnerDemoApp`. Open `PartnerDemoApp.xcodeproj` in Xcode, select a simulator, and run. The demo registers the biometric plugin and uses feature flags for a quick auto-complete flow.

## Docs
- `docs/HSBC_Journey_Agnostic_iOS_SDK.md`: Architectural overview.
- `HSBC_Develop_Guide.md`: Adding a new journey + OpenAPI (HSBC internal).
- `Third_Party_Develop_Guide.md`: Partner integration steps.
- `SECURITY_BACKLOG.md` / `OVERALL_BACKLOG.md`: Open items and gaps.
- `DONE_CHECKLIST.md`: Definition of done snapshot.

## CI
GitHub Actions (`ios-sdk` workflow) runs `swift build`/`swift test`, builds XCFramework via `scripts/build_xcframework.sh`, uploads artifacts, and creates releases on tags `v*`.

## Status & Gaps
See `OVERALL_BACKLOG.md` for remaining items (pinning/attestation hardening, schema/header templating, demo assets, ATS/AppBoundDomains, artifact verification, etc.).

## License
TBD (add your license here).
