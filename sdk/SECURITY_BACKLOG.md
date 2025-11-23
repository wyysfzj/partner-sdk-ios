# Security Hardening Backlog

| Item | Owner | Priority | Status |
| --- | --- | --- | --- |
| Cert pinning (dual pins: current + next) for native requests | Security/SDK | High | Planned |
| ATS hardened; WKAppBoundDomains; CSP example for web containers | Security/SDK | High | Planned |
| Attestation (DeviceCheck/App Attest) sending `X-HSBC-Attest` header | Security/SDK | High | Planned |
| JWS/JWE for all Bridge responses (ES256; optional JWE for sensitive plugin outputs) | Security/SDK | High | Planned |
| Resume token encryption & rotation | Security/SDK | Medium | Planned |
| Kill-switch via signed remote config | Security/SDK | Medium | Planned |
| Per-journey scopes; least privilege | Security/SDK | Medium | Planned |
| OpenTelemetry metrics & budgets (TTFP ≤ 1200ms on 4G; p95 server step ≤ 800ms) | Security/SDK | Medium | Planned |
| Chaos tests for offline/retry/idempotency | QA/SRE | Medium | Planned |
