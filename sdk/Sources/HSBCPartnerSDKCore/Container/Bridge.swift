import Foundation

#if canImport(WebKit) && canImport(UIKit)
import WebKit
import UIKit
import CryptoKit

/// Secure bridge between the WKWebView and native SDK.
@available(iOS 13.0, *)
public final class Bridge: NSObject, WKScriptMessageHandler {
    
    private enum State {
        case notReady
        case ready(origin: URL, pageNonce: String)
    }
    
    weak var webView: WKWebView?
    private var state: State = .notReady
    private let allowedOrigins: [URL]
    private let allowFileOrigins: Bool
    private var allowedMethods: Set<String>
    private static var sharedSigner: JWSSigner? = {
        #if canImport(CryptoKit)
        if #available(iOS 13.0, macOS 10.15, *) {
            return try? JWSSigner(privateKey: P256.Signing.PrivateKey(), kid: "bridge-local")
        }
        #endif
        return nil
    }()
    private let signer: JWSSigner?
    private var onIncomingEvent: ((String, [String: Any]) -> Void)?
    var outboundHook: (([String: Any]) -> Void)?
    
    public init(allowedOrigins: [URL], allowedMethods: [String], allowFileOrigins: Bool = false) {
        self.allowedOrigins = allowedOrigins
        self.allowFileOrigins = allowFileOrigins
        self.allowedMethods = Set(allowedMethods)
        self.signer = Bridge.sharedSigner
        super.init()
    }
    
    /// Attaches the bridge to the given web view and registers message handlers.
    public func attach(to webView: WKWebView) {
        self.webView = webView
        webView.configuration.userContentController.add(self, name: "hsbcBridge")
        print("[Bridge] Attached to webview; allowedOrigins=\(allowedOrigins) allowFileOrigins=\(allowFileOrigins)")
    }
    
    /// Updates the allow-list for methods; called when the step changes.
    public func updateAllowedMethods(_ methods: [String]) {
        allowedMethods = Set(methods)
    }
    
    /// Attach a listener for incoming events/requests after handshake.
    public func onEvent(_ handler: @escaping (String, [String: Any]) -> Void) {
        onIncomingEvent = handler
    }
    
    /// Emits an event to the page.
    public func emit(name: String, payload: [String: Any]) {
        send(kind: "event", name: name, id: nil, payload: payload, meta: responseMeta())
    }
    
    // MARK: - WKScriptMessageHandler
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "hsbcBridge",
              let body = message.body as? [String: Any],
              let kind = body["kind"] as? String else {
            return
        }
        process(kind: kind, body: body)
    }
    
    /// Test hook to simulate incoming messages without WKWebView plumbing.
    func process(kind: String, body: [String: Any]) {
        switch kind {
        case "event":
            handleEvent(body)
        case "request":
            handleRequest(body)
        default:
            break
        }
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(_ body: [String: Any]) {
        guard let name = body["name"] as? String else { return }
        if name == "bridge_hello" {
            guard
                let payload = body["payload"] as? [String: Any],
                let originString = payload["origin"] as? String,
                let origin = URL(string: originString),
                let pageNonce = payload["pageNonce"] as? String,
                isAllowed(origin: origin, allowed: allowedOrigins, allowFileOrigins: allowFileOrigins)
            else {
                print("[Bridge] bridge_hello rejected; payload=\(body)")
                sendForbidden(reason: SdkErrorCode.ORIGIN_BLOCKED.rawValue, eventName: "ORIGIN_BLOCKED")
                return
            }
            
            state = .ready(origin: origin, pageNonce: pageNonce)
            print("[Bridge] bridge_ready origin=\(origin) pageNonce=\(pageNonce)")
            
            let attestationProof = AttestationCollector.collect()
            let responsePayload: [String: Any] = [
                "sdkCapabilities": ["bridge.v1", "attestation.stub"],
                "sessionProofJws": attestationProof
            ]
            let meta = responseMeta()
            send(kind: "event", name: "bridge_ready", id: nil, payload: responsePayload, meta: meta)
            return
        }
        
        if let payload = body["payload"] as? [String: Any] {
            print("[Bridge] event \(name) payload=\(payload)")
            onIncomingEvent?(name, payload)
        }
    }
    
    // MARK: - Request Handling
    
    private func handleRequest(_ body: [String: Any]) {
        guard
            case .ready = state,
            let name = body["name"] as? String,
            let requestId = body["id"],
            allowedMethods.contains(name)
        else {
            sendForbidden(reason: "BRIDGE_FORBIDDEN")
            return
        }
        
        let payload = body["payload"] as? [String: Any] ?? [:]
        
        if let plugin = PluginRegistry.shared.resolve(method: name) {
            Task {
                do {
                    let result = try await plugin.handle(name, params: payload)
                    let meta = responseMeta()
                    send(kind: "response", name: name, id: requestId, payload: result, meta: meta)
                    print("[Bridge] plugin handled \(name) -> \(result)")
                } catch {
                    print("[Bridge] plugin error \(name): \(error)")
                    send(kind: "event", name: "BRIDGE_ERROR", id: requestId, payload: ["reason": "\(error)"], meta: responseMeta())
                }
            }
            return
        }
        
        onIncomingEvent?(name, payload)
        let responsePayload = ["ack": true]
        send(kind: "response", name: name, id: requestId, payload: responsePayload, meta: responseMeta())
    }
    
    // MARK: - Outbound Messaging
    
    private func send(kind: String, name: String, id: Any?, payload: [String: Any], meta: [String: Any]) {
        var envelope: [String: Any] = [
            "kind": kind,
            "name": name,
            "payload": payload,
            "meta": meta
        ]
        if let id = id {
            envelope["id"] = id
        }
        
        if let sig = sign(name: name, payload: payload, meta: meta) {
            envelope["sig"] = sig
        }
        
        outboundHook?(envelope)
        print("[Bridge] send to page kind=\(kind) name=\(name) id=\(id ?? "nil")")
        sendToPage(envelope)
    }
    
    private func sendForbidden(reason: String, eventName: String = "BRIDGE_FORBIDDEN") {
        let meta = responseMeta()
        let payload: [String: Any] = ["reason": reason]
        send(kind: "event", name: eventName, id: nil, payload: payload, meta: meta)
    }
    
    private func sendToPage(_ envelope: [String: Any]) {
        guard let webView = webView else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: []),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = "window.hsbcBridge && window.hsbcBridge.receive(\(json));"
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
    
    // MARK: - Signing
    
    private func sign(name: String, payload: [String: Any], meta: [String: Any]) -> String? {
        guard let signer = signer else { return nil }
        var toSign: [String: Any] = [
            "name": name,
            "payload": payload,
            "meta": meta
        ]
        // Consistent ordering via sorted keys serialization.
        guard let data = try? JSONSerialization.data(withJSONObject: toSign, options: [.sortedKeys]) else {
            return nil
        }
        return try? signer.sign(payload: data)
    }
    
    // MARK: - Meta helpers
    
    private func responseMeta() -> [String: Any] {
        [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "nonce": UUID().uuidString,
            "bridgeVersion": "1.1",
            "sdkVersion": HSBCPartnerSDKCore.version,
            "traceparent": newTraceparent()
        ]
    }
}

// MARK: - Attestation stub

enum AttestationCollector {
    static func collect() -> String {
        #if canImport(DeviceCheck)
        if #available(iOS 14.0, *) {
            let token = UUID().uuidString.data(using: .utf8) ?? Data()
            return token.base64EncodedString()
        }
        #endif
        return UUID().uuidString
    }
}

#else
// Non-UIKit platforms.
public final class Bridge {
    public var outboundHook: (([String: Any]) -> Void)?
    private let allowedOrigins: [URL]
    private let allowFileOrigins: Bool
    private var allowedMethods: Set<String>
    private var onIncomingEvent: ((String, [String: Any]) -> Void)?
    public init(allowedOrigins: [URL], allowedMethods: [String], allowFileOrigins: Bool = false) {
        self.allowedOrigins = allowedOrigins
        self.allowFileOrigins = allowFileOrigins
        self.allowedMethods = Set(allowedMethods)
    }
    public func attach(to: Any) {}
    public func emit(name: String, payload: [String: Any]) {
        outboundHook?(["name": name, "payload": payload, "kind": "event"])
    }
    public func process(kind: String, body: [String: Any]) {
        switch kind {
        case "event":
            guard let name = body["name"] as? String else { return }
            if name == "bridge_hello" {
                guard
                    let payload = body["payload"] as? [String: Any],
                    let originString = payload["origin"] as? String,
                    let origin = URL(string: originString),
                    isAllowed(origin: origin, allowed: allowedOrigins, allowFileOrigins: allowFileOrigins)
                else {
                    outboundHook?(["name": "ORIGIN_BLOCKED"])
                    return
                }
        outboundHook?(["name": "bridge_ready", "payload": ["sessionProofJws": "stub"], "sig": "stub"])
            } else if let payload = body["payload"] as? [String: Any] {
                print("[Bridge(non-UIKit)] event \(name) payload=\(payload)")
                onIncomingEvent?(name, payload)
            }
        case "request":
            guard
                let name = body["name"] as? String,
                allowedMethods.contains(name)
            else {
                outboundHook?(["name": "BRIDGE_FORBIDDEN"])
                return
            }
            if let payload = body["payload"] as? [String: Any] {
                onIncomingEvent?(name, payload)
            }
        default:
            break
        }
    }
    public func onEvent(_ handler: @escaping (String, [String: Any]) -> Void) {
        onIncomingEvent = handler
    }
    public func updateAllowedMethods(_ methods: [String]) {
        allowedMethods = Set(methods)
    }
}
#endif
