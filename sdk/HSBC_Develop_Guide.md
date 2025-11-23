# Guide: Adding a New Journey to the HSBC Journey-Agnostic iOS SDK

## 1. Prepare the Journey Manifest (JM v1.1)
- Create a JSON manifest:
  - Top-level: `manifestVersion: "1.1"`, `minSdk`, `journeyId` (e.g., "card_application"), `oapiBundle` (URL to OpenAPI JSON), `startStep`, `headers`, `security` (allowedOrigins, pinning, attestation?, requireHandshake), `resumePolicy?`, `steps`, `signature` (detached JWS).
  - Steps: type (`web`/`native`/`server`/`terminal`), `url` or `plugin`, `bindings` (onEvent → call.operationId, argsFrom?, headers?, onSuccessEmit?, onErrorEmit?), transitions `on[event]` → {to?, emit?, guardExpr?}, `result`, `bridgeAllow`, `idempotencyKey`.
- Sign the manifest (detached JWS excluding the signature field). For local dev you can bypass signature verification via `featureFlags["disableManifestSignatureVerification"]=true`.

## 2. Prepare the OpenAPI Bundle (OAS 3)
- Ensure every `operationId` referenced in manifest bindings exists in the OpenAPI document.
- Include a `servers` list with the base URL; define paths/methods with `operationId` and schemas.
- Save the OpenAPI JSON; the manifest’s `oapiBundle` should point to this file/URL.

## 3. Host or Provide Local Files (Dev)
- Dev/testing: place `manifest.json` and OpenAPI JSON on disk (file://) and set `HSBCInitConfig.remoteConfigURL` to that directory.
- Production/staging: host on HTTPS endpoints and set `remoteConfigURL` accordingly.

## 4. Journey Pages (Web Steps)
- Hosted pages must implement the bridge protocol: send `bridge_hello`, handle `bridge_ready`, and send requests/events as per Bridge v1.1.
- Set `allowedOrigins` in the manifest to match hosted domains.

## 5. Integrate with SDK Runtime
- No SDK code changes required if manifest/OAS are correct. The SDK will:
  - Load manifest via `ManifestLoader`, validate `minSdk` and `allowedOrigins`.
  - Resolve `operationId`s via `OpenAPIResolver` (binding validation).
  - Drive `StateMachine` via steps/on/guardExpr/bindings.
  - Present web steps via `HybridContainer`, enforce origins via `WebPolicies`.
  - Call APIs via `ApiClient` using the OpenAPI bundle.

## 6. Test Locally
- Configure `HSBCInitConfig` with `remoteConfigURL` pointing to your local folder (manifest/OAS).
- Use dev flags if needed (e.g., `allowFileOrigins` for file://, `disableManifestSignatureVerification`).
- Run the demo app or your harness to `startJourney` with the new `journeyId` and a `contextToken`.

## 7. Verify Bindings & Transitions
- Confirm `ApiClient` resolves operationIds and uses the expected base URL from OAS servers.
- Ensure `on` events trigger transitions; `guardExpr` blocks/allows as intended; `timeoutMs` triggers “timeout”; bindings emit `onSuccess`/`onError` events.

## 8. Production Readiness
- Enable pinning (`manifest.security.pinning=true`) with real pins once implemented.
- Ensure ATS/WKAppBoundDomains cover hosted domains.
- Use signed manifests and attestation configuration as required.

## 9. CI/Release
- Version and host manifest/OAS.
- Run `swift test` and CI workflow to build/test and produce XCFramework artifacts if distributing binaries.

## Quick Checklist
- [ ] Manifest v1.1 created, signed (or dev bypass flag set), hosted/local.
- [ ] OpenAPI bundle contains all manifest `operationId`s.
- [ ] Allowed origins set; pages implement bridge_hello/requests.
- [ ] Tested via `remoteConfigURL` and `startJourney(journeyId: …)`.
- [ ] Pinning/ATS/AppBoundDomains planned for prod.
