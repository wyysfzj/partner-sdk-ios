import Foundation

/// Structure representing a journey event with metadata.
public struct JourneyEvent {
    /// Name of the event.
    public let name: String
    /// Attributes associated with the event.
    public let attributes: [String: Any]
    /// Timestamp when the event occurred.
    public let ts: Date
    /// Correlation ID for tracing the journey.
    public let correlationId: String
}

/// Singleton event bus for emitting and listening to journey events.
public final class EventBus {
    
    /// Shared singleton instance.
    public static let shared = EventBus()
    
    /// Signature for the external listener.
    public typealias ExternalListener = (String, [String: Any]) -> Void
    
    private var externalListener: ExternalListener?
    private let queue = DispatchQueue(label: "com.hsbc.partnersdk.eventbus", attributes: .concurrent)
    
    private init() {}
    
    /// Sets the single external listener for events.
    /// - Parameter listener: The closure to receive events.
    public func setListener(_ listener: @escaping ExternalListener) {
        queue.async(flags: .barrier) {
            self.externalListener = listener
        }
    }
    
    /// Emits an event to the listener.
    /// - Parameter event: The event to emit.
    func emit(_ event: JourneyEvent) {
        queue.async {
            self.externalListener?(event.name, event.attributes)
        }
    }
    
    // MARK: - Helpers
    
    /// Emits a journey begin event.
    public func journeyBegin(journeyId: String, correlationId: String) {
        emit(JourneyEvent(name: "journey_begin", attributes: ["journeyId": journeyId], ts: Date(), correlationId: correlationId))
    }
    
    /// Emits a step enter event.
    public func stepEnter(stepName: String, correlationId: String) {
        emit(JourneyEvent(name: "step_enter", attributes: ["step": stepName], ts: Date(), correlationId: correlationId))
    }
    
    /// Emits a step exit event.
    public func stepExit(stepName: String, correlationId: String) {
        emit(JourneyEvent(name: "step_exit", attributes: ["step": stepName], ts: Date(), correlationId: correlationId))
    }
    
    /// Emits an API call event.
    public func apiCall(url: String, correlationId: String) {
        emit(JourneyEvent(name: "api_call", attributes: ["url": url], ts: Date(), correlationId: correlationId))
    }
    
    /// Emits a bridge message event.
    public func bridge(message: String, correlationId: String) {
        emit(JourneyEvent(name: "bridge_message", attributes: ["message": message], ts: Date(), correlationId: correlationId))
    }
    
    /// Emits an error event.
    public func error(code: String, message: String, correlationId: String) {
        emit(JourneyEvent(name: "error", attributes: ["code": code, "message": message], ts: Date(), correlationId: correlationId))
    }
    
    /// Emits a result event.
    public func result(success: Bool, correlationId: String) {
        emit(JourneyEvent(name: "result", attributes: ["success": success], ts: Date(), correlationId: correlationId))
    }
}
