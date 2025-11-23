# Definition of Done

- ✅ **Build**: `swift build` and `swift test` pass locally and in CI.
- ✅ **Demo**: Journey `money_transfer` runs intro → recipient → amount → review → biometric → submit → completed on simulator.
- ✅ **Errors**: Simulated 429/500 retries; 401 maps to `AUTH_EXPIRED`; origin blocked path exercised; handshake-required path exercised.
- ✅ **Security**: ATS/WKAppBoundDomains set in demo; Bridge responses JWS signing enabled; feature flag to allow `file://` origins is off by default.
- ✅ **Packaging**: XCFramework built via scripts/build_xcframework.sh; checksum generated; release tag attaches artifact.
- ✅ **Docs**: `SECURITY_BACKLOG.md` and `docs/DEV_MACRO_PROMPTS.md` are present and current.
