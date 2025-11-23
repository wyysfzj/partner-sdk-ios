import SwiftUI
import HSBCPartnerSDKCore
import HSBCPlugins

struct ContentView: View {
    @State private var lastResult: String = "No result yet"
    
    var body: some View {
        VStack(spacing: 16) {
            Button("Initialize SDK", action: initializeSDK)
                .buttonStyle(.borderedProminent)
            
            Button("Start Money Transfer", action: startJourney)
                .buttonStyle(.bordered)
            
            Text(lastResult)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding()
    }
    
    private func initializeSDK() {
        guard let manifestURL = Bundle.main.url(forResource: "demo_manifest", withExtension: "json") else {
            lastResult = "Demo manifest missing"
            return
        }
        PluginRegistry.shared.register(BiometricAuthPlugin())
        let config = HSBCInitConfig(
            environment: .sandbox,
            partnerId: "demo-partner",
            clientId: "demo-client",
            redirectScheme: "partnerdemo",
            locale: Locale(identifier: "en_US"),
            remoteConfigURL: manifestURL,
            featureFlags: [
                "allowFileOrigins": true,
                "demoAutoComplete": false,
                "disableManifestSignatureVerification": true
            ],
            telemetryOptIn: true
        )
        HSBCPartnerSdk.initialize(config: config)
        HSBCPartnerSdk.setEventListener { name, attributes in
            print("SDK Event: \(name) -> \(attributes)")
            lastResult = "Event: \(name)"
        }
        lastResult = "SDK initialized"
    }
    
    private func startJourney() {
        guard let presenter = topController() else {
            lastResult = "No presenter"
            return
        }
        lastResult = "Starting journey..."
        let params = JourneyStartParams(
            journeyId: "money_transfer",
            contextToken: "mtok_demo"
        )
        HSBCPartnerSdk.startJourney(from: presenter, params: params) { result in
            DispatchQueue.main.async {
                presenter.presentedViewController?.dismiss(animated: true, completion: nil)
                print("[Demo] Journey completion: \(result)")
                switch result {
                case .completed(let payload):
                    lastResult = "Completed: \(payload)"
                case .pending(let payload):
                    lastResult = "Pending: \(payload)"
                case .cancelled:
                    lastResult = "Cancelled"
                case .failed(let code, let message, let recoverable):
                    lastResult = "Failed \(code) (\(recoverable ? "recoverable" : "fatal")): \(message)"
                }
            }
        }
    }
}

/// Helper to locate the top-most UIKit controller for presentation.
func topController(base: UIViewController? = UIApplication.shared.connectedScenes
    .compactMap { ($0 as? UIWindowScene)?.keyWindow }
    .first?.rootViewController) -> UIViewController? {
    if let nav = base as? UINavigationController {
        return topController(base: nav.visibleViewController)
    }
    if let tab = base as? UITabBarController {
        return topController(base: tab.selectedViewController)
    }
    if let presented = base?.presentedViewController {
        return topController(base: presented)
    }
    return base
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
