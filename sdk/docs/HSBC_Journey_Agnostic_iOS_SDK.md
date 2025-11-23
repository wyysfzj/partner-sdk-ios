# HSBC Journey-Agnostic iOS SDK

## 1. Overview
The HSBC Partner SDK enables third-party apps to embed HSBC journeys (e.g., Account Opening, Money Transfer) via signed manifests and OpenAPI bundles. The SDK provides a stable public API, a secure hybrid container, a JS bridge, and a runtime engine that interprets manifests to drive flows without code changes per journey.

## 2. Public Surface
- **HSBCInitConfig**: environment, partnerId, clientId, redirectScheme, locale, remoteConfigURL?, featureFlags, telemetryOptIn.
- **JourneyStartParams**: journeyId, contextToken, resumeToken?, productCode?, campaignId?, trackingContext, capabilitiesOverride?.
- **JourneyResult**: completed(payload), pending(payload), cancelled, failed(code,message,recoverable).
- **API** (`HSBCPartnerSdk`): initialize(config), setEventListener((name, attributes)), startJourney(from:UIViewController, params, completion).

## 3. Core Runtime
- **RuntimeEngine**: Loads manifest, resolves OpenAPI, creates ApiClient, orchestrates StateMachine, wires Bridge, presents WKWebView via HybridContainer, maps terminal steps to JourneyResult.
- **StateMachine**: Holds currentStepId, transitions via manifest `on` events, guardExpr evaluator (==, !=, >, <, &&, || with dotted lookups), bindings -> ApiClient calls, timeoutMs emits `timeout`, callbacks for onStepEnter/onTerminal/onError.
- **SessionManager**: correlationId/context/resume/idempotencyKey; snapshots {journeyId, stepPointer, idempotencyKey, ts} stored in Keychain (ThisDeviceOnly); startSession(contextToken,resumeToken); load/save snapshot.
- **EventBus**: Emits journey_begin, step_enter/exit, api_call, bridge_message, error, result; forwards to partner listener.

## 4. Data Contracts
- **Manifest v1.1** (`ManifestModels.swift`): manifestVersion, minSdk, journeyId, oapiBundle, startStep, headers, security {allowedOrigins, pinning, attestation?, requireHandshake}, resumePolicy?, steps, signature. Steps include type (web/native/server/terminal), url/plugin, bindings {onEvent, call.operationId, argsFrom?, headers?, onSuccessEmit?, onErrorEmit?}, on transitions {to?, emit?, guardExpr?}, result, bridgeAllow, idempotencyKey.
- **OpenAPIResolver**: Parses OpenAPI JSON, maps operationId -> (method, path), builds URLRequest, validates manifest bindings reference existing operationIds.
- **AnyCodable**: Supports arbitrary JSON payloads in manifest fields.

## 5. Networking
- **ApiClient**: Resolves operationId to URLRequest, adds traceparent and optional X-Idempotency-Key, retries with backoff+jitter on 408/429/5xx, respects Retry-After, maps HTTP status to SdkErrorCode (AUTH_EXPIRED, NET_TIMEOUT, IDEMPOTENT_REPLAY, VALIDATION_FAIL, RATE_LIMITED, UNKNOWN), optional pinning delegate (basic).
- **SdkErrorCode**: Canonical error codes for mapping JourneyResult failures.

## 6. Container & Bridge
- **HybridContainer**: ASWebAuthenticationSession signInIfNeeded (ephemeral), presents WKWebView (JS enabled, no popups/nav gestures), navigation delegate enforces origins via WebPolicies, optional dev flag for file://.
- **WebPolicies**: isAllowed(origin, allowed, allowFileOrigins=false); production assumes ATS + WKAppBoundDomains.
- **Bridge v1.1**: Handshake `bridge_hello` -> `bridge_ready` (sdkCapabilities, sessionProofJws), states notReady/ready, per-step allowedMethods, plugin dispatch via PluginRegistry, signs outbound envelopes (JWS), emits BRIDGE_FORBIDDEN/ORIGIN_BLOCKED.

## 7. Plugins
- **JourneyPlugin protocol**: name, canHandle(method), handle(method, params) async -> payload.
- **BiometricAuthPlugin**: performBiometric via LocalAuthentication; returns PASS or errors (user cancel/SCA required).
- **PluginRegistry**: Singleton registration/resolution for bridge-dispatched methods.

## 8. Security Notes (Current State)
- Pinning: Basic trust delegate; pins not enforced/dual-pinned per host.
- Attestation: Stub collector; bridge signing uses ephemeral key per process.
- Manifest verification: minSdk + allowedOrigins validation; signature verification behind feature flag; schema enforcement and header templating not implemented.
- Origin checks: HTTPS allow-list; dev flag can allow file://.

## 9. Demo App
- Location: `examples/PartnerDemoApp`.
- SwiftUI with “Initialize SDK” and “Start Money Transfer”; registers BiometricAuthPlugin; demo flags enable file:// and auto-complete result for a quick walkthrough.
- UITest scaffold exists (does not yet drive WKWebView interactions).

## 10. CI/CD
- Workflow: `.github/workflows/ios-sdk.yml` builds/tests in `sdk/`, runs `scripts/build_xcframework.sh`, uploads XCFramework artifact, creates release on tags v*.

## 11. Testing
- Unit tests: Manifest decoding/validation, ApiClient retries, Bridge handshake events, StateMachine transitions/guards/timeouts, SessionManager snapshots, OpenAPI operationId validation.
- UITest: Basic app launch/status check (WKWebView interactions pending).

## 12. Known Gaps (summarized)
- Pinning (dual pins, per-host), attestation binding, JWE for sensitive payloads.
- Manifest schema/header templating, remote config/kill-switch consumption.
- Runtime error mapping driven by manifest policy; nuanced failures (pinning/attestation/origin/handshake).
- Resume token encryption/rotation and resumePolicy adherence.
- Bridge signing with stable keypair/public key distribution; JWE option; richer state updates.
- Web policies: ATS/AppBoundDomains/CSP and dev file flag governance.
- OAS server/base URL safety; full manifest↔OAS consistency.
- ApiClient: validation body parsing for MORE_INFO/COMPLIANCE_HOLD; plugin error mapping to SdkErrorCode.
- Plugins: only biometric; registry not auto-wired in runtime; error mapping to JourneyResult.
- Demo: lacks real pages/manifest; UITest doesn’t drive WKWebView; ATS/AppBoundDomains not set.
- CI/release: Xcode path hardcoded; artifacts not verified beyond shasum.

## 13. Next Steps
- Prioritize security hardening (pinning, attestation, schema enforcement).
- Wire real manifest/OAS and demo pages for an end-to-end Money Transfer flow.
- Improve runtime error handling based on manifest-defined policies.
- Strengthen demo/UITest to exercise WKWebView and bridge interactions.
