import Foundation
#if canImport(UIKit)
import UIKit
#else
import class Foundation.NSObject
/// Lightweight fallback so non-iOS SwiftPM invocations (e.g. `swift test` on macOS) can compile.
public typealias UIViewController = NSObject
#endif

/// Immutable configuration values required to bootstrap the HSBC Partner SDK.
public struct HSBCInitConfig {

    /// Supported runtime environments for the HSBC Partner SDK.
    public enum Environment {
        /// Use sandbox services, typically backed by non-production infrastructure.
        case sandbox
        /// Use production services that handle real customer data.
        case production
    }

    /// The environment that determines which backend services the SDK communicates with.
    public let environment: Environment

    /// Identifier provided by HSBC to uniquely represent the partner.
    public let partnerId: String

    /// Identifier used to authenticate the partner client application.
    public let clientId: String

    /// Custom URL scheme that the host application handles to receive callbacks.
    public let redirectScheme: String

    /// Locale that controls language and regional formatting for the runtime experience.
    public let locale: Locale

    /// Optional remote configuration endpoint that can supply dynamic overrides.
    public let remoteConfigURL: URL?

    /// Feature flag map that toggles optional behaviours within the SDK.
    public let featureFlags: [String: Bool]

    /// Indicates whether the end user has opted into telemetry collection.
    public let telemetryOptIn: Bool

    /// Creates a new configuration instance.
    /// - Parameters:
    ///   - environment: The environment that should be used for network requests.
    ///   - partnerId: Unique partner identifier allocated by HSBC.
    ///   - clientId: Client identifier used for authentication flows.
    ///   - redirectScheme: URL scheme handled by the hosting application.
    ///   - locale: Locale that influences language and formatting.
    ///   - remoteConfigURL: Optional endpoint that exposes remote overrides.
    ///   - featureFlags: Dictionary of feature names to boolean states.
    ///   - telemetryOptIn: Flag that reflects the user telemetry consent status.
    public init(
        environment: Environment,
        partnerId: String,
        clientId: String,
        redirectScheme: String,
        locale: Locale,
        remoteConfigURL: URL? = nil,
        featureFlags: [String: Bool] = [:],
        telemetryOptIn: Bool
    ) {
        self.environment = environment
        self.partnerId = partnerId
        self.clientId = clientId
        self.redirectScheme = redirectScheme
        self.locale = locale
        self.remoteConfigURL = remoteConfigURL
        self.featureFlags = featureFlags
        self.telemetryOptIn = telemetryOptIn
    }
}

#if !canImport(UIKit)
/// Minimal fallback runtime used when UIKit is unavailable (e.g. SwiftPM on macOS).
private enum FallbackRuntimeEngine {
    static func start(
        from viewController: UIViewController,
        config: HSBCInitConfig,
        params: JourneyStartParams,
        eventListener: HSBCPartnerSdk.EventListener?,
        completion: @escaping (JourneyResult) -> Void
    ) {
        let error = JourneyResult.failed(
            code: "hsbc.partnersdk.runtime.unavailable",
            message: "RuntimeEngine is only available on UIKit platforms.",
            recoverable: false
        )
        DispatchQueue.main.async {
            completion(error)
        }
    }
}
#endif

/// Parameters that describe how a journey should be started.
public struct JourneyStartParams {

    /// Unique identifier that maps to the journey configuration to launch.
    public let journeyId: String

    /// JWT or opaque token that authorises the journey execution.
    public let contextToken: String

    /// Optional token that resumes an in-progress journey.
    public let resumeToken: String?

    /// Optional code that identifies the product being offered.
    public let productCode: String?

    /// Optional identifier that attributes the journey to a specific marketing campaign.
    public let campaignId: String?

    /// Additional key-value pairs that provide tracing metadata for analytics.
    public let trackingContext: [String: String]

    /// Overrides that enable or disable specific runtime capabilities when present.
    public let capabilitiesOverride: [String: Bool]?

    /// Creates journey launch parameters.
    /// - Parameters:
    ///   - journeyId: Identifier of the journey to load.
    ///   - contextToken: Authorisation token tied to the current user session.
    ///   - resumeToken: Optional token used to resume a previously saved session.
    ///   - productCode: Optional product identifier associated with the journey.
    ///   - campaignId: Optional campaign identifier for marketing attribution.
    ///   - trackingContext: Additional analytics context expressed as key-value pairs.
    ///   - capabilitiesOverride: Optional overrides for runtime capability flags.
    public init(
        journeyId: String,
        contextToken: String,
        resumeToken: String? = nil,
        productCode: String? = nil,
        campaignId: String? = nil,
        trackingContext: [String: String] = [:],
        capabilitiesOverride: [String: Bool]? = nil
    ) {
        self.journeyId = journeyId
        self.contextToken = contextToken
        self.resumeToken = resumeToken
        self.productCode = productCode
        self.campaignId = campaignId
        self.trackingContext = trackingContext
        self.capabilitiesOverride = capabilitiesOverride
    }
}

/// Result emitted when a journey finishes or transitions into a new state.
public enum JourneyResult {
    /// The journey completed successfully with an optional payload.
    case completed(payload: [String: Any])
    /// The journey is still in progress and requires further action outside the SDK.
    case pending(payload: [String: Any])
    /// The journey was cancelled by the end user.
    case cancelled
    /// The journey failed with a code, human readable message, and recovery hint.
    case failed(code: String, message: String, recoverable: Bool)
}

/// Public facade that exposes the HSBC Partner SDK functionality.
public enum HSBCPartnerSdk {

    /// Closure signature used to emit telemetry events from the SDK.
    public typealias EventListener = (String, [String: Any]) -> Void

    /// Container that holds mutable SDK state.
    private struct State {
        /// The last configuration supplied by the hosting application.
        var config: HSBCInitConfig?
        /// Listener that receives emitted SDK events.
        var eventListener: EventListener?
    }

    /// Current SDK state shared across the module.
    private static var state = State()
    /// Serial queue that protects access to the current state.
    private static let stateQueue = DispatchQueue(label: "com.hsbc.partnersdk.state", attributes: .concurrent)

    /// Bootstraps the SDK with the provided configuration.
    /// - Parameter config: Configuration values that control networking, localisation, and feature behaviour.
    public static func initialize(config: HSBCInitConfig) {
        updateState { mutableState in
            mutableState.config = config
        }
    }

    /// Registers a closure that receives analytics and lifecycle events from the SDK.
    /// - Parameter listener: Closure that will be invoked with the event name and associated attributes.
    public static func setEventListener(_ listener: @escaping EventListener) {
        updateState { mutableState in
            mutableState.eventListener = listener
        }
    }

    /// Launches a journey from the supplied view controller.
    /// - Parameters:
    ///   - viewController: Host view controller responsible for presenting runtime UI.
    ///   - params: Journey parameters that describe what should be launched.
    ///   - completion: Completion handler invoked when the journey produces a result.
    @MainActor
    public static func startJourney(
        from viewController: UIViewController,
        params: JourneyStartParams,
        completion: @escaping (JourneyResult) -> Void
    ) {
        let snapshot = stateQueue.sync { state }

        guard let storedConfig = snapshot.config else {
            let error = JourneyResult.failed(
                code: "hsbc.partnersdk.uninitialized",
                message: "HSBCPartnerSdk.initialize(config:) must be called before starting a journey.",
                recoverable: false
            )
            completion(error)
            return
        }

        #if canImport(UIKit)
        RuntimeEngine.start(
            from: viewController,
            config: storedConfig,
            params: params,
            eventListener: snapshot.eventListener,
            completion: completion
        )
        #else
        FallbackRuntimeEngine.start(
            from: viewController,
            config: storedConfig,
            params: params,
            eventListener: snapshot.eventListener,
            completion: completion
        )
        #endif
    }

    /// Executes a mutation on the stored state using a barrier-aware queue.
    /// - Parameter change: Closure that mutates the state in a thread-safe way.
    private static func updateState(_ change: @escaping (inout State) -> Void) {
        stateQueue.async(flags: .barrier) {
            change(&state)
        }
    }
}
