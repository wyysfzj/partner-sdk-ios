import Foundation
#if canImport(UIKit)
import UIKit
import WebKit

@available(iOS 13.0, *)
public enum RuntimeEngine {
    
    public typealias StartHandler = (
        UIViewController,
        HSBCInitConfig,
        JourneyStartParams,
        HSBCPartnerSdk.EventListener?,
        @escaping (JourneyResult) -> Void
    ) -> Void
    
    static var startHandler: StartHandler?
    
    public static func start(
        from presenter: UIViewController,
        config: HSBCInitConfig,
        params: JourneyStartParams,
        eventListener: HSBCPartnerSdk.EventListener?,
        completion: @escaping (JourneyResult) -> Void
    ) {
        if let handler = startHandler {
            handler(presenter, config, params, eventListener, completion)
            return
        }
        
        Task { @MainActor in
            await runDefault(
                presenter: presenter,
                config: config,
                params: params,
                eventListener: eventListener,
                completion: completion
            )
        }
    }
    
    @MainActor
    private static func runDefault(
        presenter: UIViewController,
        config: HSBCInitConfig,
        params: JourneyStartParams,
        eventListener: HSBCPartnerSdk.EventListener?,
        completion: @escaping (JourneyResult) -> Void
    ) async {
        EventBus.shared.journeyBegin(journeyId: params.journeyId, correlationId: SessionManager.shared.correlationId)
        SessionManager.shared.startSession(contextToken: params.contextToken, resumeToken: params.resumeToken)
        
        // 1. Load manifest
        let manifestLoader = ManifestLoader()
        let manifest: Manifest
        do {
            manifest = try await manifestLoader.load(
                journeyId: params.journeyId,
                contextToken: params.contextToken,
                config: config,
                keyStore: KeyStore.shared
            )
        } catch {
            print("[RuntimeEngine] Manifest load failed: \(error)")
            completion(.failed(code: SdkErrorCode.UNKNOWN.rawValue, message: "\(error)", recoverable: false))
            return
        }
        print("[RuntimeEngine] Loaded manifest journeyId=\(manifest.journeyId) startStep=\(manifest.startStep) allowFileOrigins=\(config.featureFlags["allowFileOrigins"] == true)")
        
        // 2. Resolve OAS and ApiClient
        guard let resolverData = try? Data(contentsOf: manifest.oapiBundle),
              let resolver = try? OpenAPIResolver(openAPIData: resolverData) else {
            print("[RuntimeEngine] OpenAPI resolve failed for \(manifest.oapiBundle)")
            completion(.failed(code: "oas_resolve_failed", message: "Unable to resolve OpenAPI", recoverable: false))
            return
        }
        
        let baseURL: URL
        if let serversObject = try? JSONSerialization.jsonObject(with: resolverData) as? [String: Any],
           let servers = serversObject["servers"] as? [[String: Any]],
           let urlString = servers.first?["url"] as? String,
           let url = URL(string: urlString) {
            baseURL = url
        } else {
            baseURL = manifest.oapiBundle.deletingLastPathComponent()
        }
        
        let apiClient = ApiClient(baseURL: baseURL, resolver: resolver, pinningEnabled: manifest.security.pinning)
        print("[RuntimeEngine] Using baseURL=\(baseURL.absoluteString)")
        
        // 3. Auth if required (stub: always skip unless requireHandshake)
        if manifest.security.requireHandshake {
            do {
                _ = try await HybridContainer.signInIfNeeded(authURL: manifest.oapiBundle, redirectScheme: config.redirectScheme)
            } catch {
                completion(.failed(code: SdkErrorCode.AUTH_EXPIRED.rawValue, message: "\(error)", recoverable: false))
                return
            }
        }
        
        do {
            try resolver.validateOperationIds(manifest: manifest)
        } catch {
            completion(.failed(code: SdkErrorCode.VALIDATION_FAIL.rawValue, message: "Manifest references missing operationIds", recoverable: false))
            return
        }
        
        // 4. Bridge and state machine
        let allowedOrigins = manifest.security.allowedOrigins
        let startStepId = manifest.startStep
        let steps = manifest.steps
        let allowFileOrigins = config.featureFlags["allowFileOrigins"] == true
        
        let bridge = Bridge(
            allowedOrigins: allowedOrigins,
            allowedMethods: steps[startStepId]?.bridgeAllow ?? [],
            allowFileOrigins: allowFileOrigins
        )
        
        var stateMachine: StateMachine?
        let machine = StateMachine(
            journeyId: manifest.journeyId,
            steps: steps,
            startStepId: startStepId,
            apiClient: apiClient,
            emitToPage: { name, payload in
                bridge.emit(name: name, payload: payload)
            }
        )
        stateMachine = machine
        
        machine.onStepEnter = { stepId in
            if let allows = steps[stepId]?.bridgeAllow {
                bridge.updateAllowedMethods(allows)
            }
        }
        
        machine.onTerminal = { step in
            EventBus.shared.result(success: true, correlationId: SessionManager.shared.correlationId)
            let payload: [String: Any]
            if let result = step.result {
                payload = result.mapValues { $0.value }
            } else {
                payload = [:]
            }
            completion(.completed(payload: payload))
        }
        
        machine.onError = { code, recoverable, message in
            completion(.failed(code: code.rawValue, message: message, recoverable: recoverable))
        }
        
        bridge.onEvent { name, payload in
            stateMachine?.handleEvent(name: name, payload: payload)
            if name == "ORIGIN_BLOCKED" {
                completion(.failed(code: SdkErrorCode.ORIGIN_BLOCKED.rawValue, message: "Origin blocked", recoverable: false))
            }
        }
        
        // 5. Present first step
        print("[RuntimeEngine] Presenting step \(startStepId) url=\(steps[startStepId]?.url?.absoluteString ?? manifest.oapiBundle.absoluteString)")
        _ = HybridContainer.presentStepWebView(
            on: presenter,
            url: steps[startStepId]?.url ?? manifest.oapiBundle,
            allowedOrigins: allowedOrigins,
            bridge: bridge,
            allowFileOrigins: allowFileOrigins
        )
        
        if config.featureFlags["demoAutoComplete"] == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                completion(.completed(payload: ["demo": true]))
            }
        }
    }
}
#endif
