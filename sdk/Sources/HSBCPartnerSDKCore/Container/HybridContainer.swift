import Foundation

#if canImport(UIKit) && canImport(WebKit) && canImport(AuthenticationServices)
import UIKit
import WebKit
import AuthenticationServices

/// Hosts hybrid web experiences and authentication surfaces.
@available(iOS 13.0, *)
public enum HybridContainer {
    
    /// Runs OIDC sign-in if required using ASWebAuthenticationSession.
    /// - Parameters:
    ///   - authURL: The authorization URL to load.
    ///   - redirectScheme: The app scheme to return to.
    /// - Returns: The redirect URL provided to the app on completion.
    public static func signInIfNeeded(authURL: URL, redirectScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: redirectScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? ASWebAuthenticationSessionError(.canceledLogin))
                }
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = PresentationContextProvider()
            if session.start() == false {
                continuation.resume(throwing: ASWebAuthenticationSessionError(.presentationContextNotProvided))
            }
        }
    }
    
    /// Presents a guarded WKWebView for journey steps.
    /// - Parameters:
    ///   - on: The presenting view controller.
    ///   - url: The initial URL to load.
    ///   - allowedOrigins: Whitelisted origins for navigation.
    ///   - bridge: Bridge used to communicate with native.
    /// - Returns: The view controller that was presented.
    public static func presentStepWebView(
        on presenter: UIViewController,
        url: URL,
        allowedOrigins: [URL],
        bridge: Bridge,
        allowFileOrigins: Bool = false
    ) -> UIViewController {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.websiteDataStore = .nonPersistent()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        
        bridge.attach(to: webView)
        
        let controller = WebViewController(webView: webView, initialURL: url, allowedOrigins: allowedOrigins, allowFileOrigins: allowFileOrigins)
        controller.modalPresentationStyle = .formSheet
        presenter.present(controller, animated: true, completion: nil)
        return controller
    }
}

// MARK: - Helpers

@available(iOS 13.0, *)
private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

private final class GuardedNavigationDelegate: NSObject, WKNavigationDelegate {
    let allowedOrigins: [URL]
    let allowFileOrigins: Bool
    init(allowedOrigins: [URL], allowFileOrigins: Bool) {
        self.allowedOrigins = allowedOrigins
        self.allowFileOrigins = allowFileOrigins
    }
    
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let targetURL = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        
        // Only allow HTTPS origins on the allow-list.
        let origin = URL(string: "\(targetURL.scheme ?? "")://\(targetURL.host ?? "")")
        let allowed = origin.flatMap { isAllowed(origin: $0, allowed: allowedOrigins, allowFileOrigins: allowFileOrigins) } ?? false
        print("[HybridContainer] decidePolicy url=\(targetURL.absoluteString) origin=\(origin?.absoluteString ?? "nil") allowed=\(allowed)")
        if allowed {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[HybridContainer] didFinish url=\(webView.url?.absoluteString ?? "nil")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[HybridContainer] didFail url=\(webView.url?.absoluteString ?? "nil") error=\(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[HybridContainer] didFailProvisional url=\(webView.url?.absoluteString ?? "nil") error=\(error)")
    }
}

private final class NoopUIDelegate: NSObject, WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Prevent new windows/popups.
        return nil
    }
}

private final class WebViewController: UIViewController {
    private let webView: WKWebView
    private let initialURL: URL
    private let navDelegate: GuardedNavigationDelegate
    private let uiDelegate: NoopUIDelegate
    
    init(webView: WKWebView, initialURL: URL, allowedOrigins: [URL], allowFileOrigins: Bool) {
        self.webView = webView
        self.initialURL = initialURL
        self.navDelegate = GuardedNavigationDelegate(allowedOrigins: allowedOrigins, allowFileOrigins: allowFileOrigins)
        self.uiDelegate = NoopUIDelegate()
        super.init(nibName: nil, bundle: nil)
        self.webView.navigationDelegate = navDelegate
        self.webView.uiDelegate = uiDelegate
    }
    
    required init?(coder: NSCoder) {
        nil
    }
    
    override func loadView() {
        view = webView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if initialURL.isFileURL {
            let dir = initialURL.deletingLastPathComponent()
            let attrs = (try? FileManager.default.attributesOfItem(atPath: initialURL.path))
            let size = attrs?[.size] as? NSNumber
            let exists = FileManager.default.fileExists(atPath: initialURL.path)
            print("[HybridContainer] Loading file URL: \(initialURL.absoluteString), exists=\(exists), size=\(size ?? -1)")
            if exists {
                webView.loadFileURL(initialURL, allowingReadAccessTo: dir)
            } else {
                if let htmlData = try? Data(contentsOf: initialURL),
                   let html = String(data: htmlData, encoding: .utf8) {
                    webView.loadHTMLString(html, baseURL: dir)
                    return
                }
                webView.loadHTMLString("<h1>Demo page missing</h1><p>\(initialURL.absoluteString)</p>", baseURL: dir)
            }
        } else {
            print("[HybridContainer] Loading remote URL: \(initialURL.absoluteString)")
            webView.load(URLRequest(url: initialURL))
        }
    }
}

#else
// Minimal stubs for non-UIKit platforms so the package builds on macOS/Linux.
public enum HybridContainer {
    public static func signInIfNeeded(authURL: URL, redirectScheme: String) async throws -> URL {
        throw NSError(domain: "HybridContainer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported platform"])
    }
    public static func presentStepWebView(on presenter: AnyObject, url: URL, allowedOrigins: [URL], bridge: AnyObject) -> AnyObject {
        fatalError("Unsupported platform")
    }
}
#endif
