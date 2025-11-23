import Foundation

/// Abstraction over ApiClient for easier testing.
public protocol ApiCalling {
    func call(
        operationId: String,
        body: [String: Any]?,
        headers: [String: String],
        idempotencyKey: String?
    ) async throws -> (status: Int, headers: [AnyHashable: Any], body: Data)
}

@available(iOS 13.0, macOS 10.15, *)
extension ApiClient: ApiCalling {}

/// Drives journey state transitions and bindings based on the manifest.
@available(iOS 13.0, macOS 10.15, *)
public final class StateMachine {
    
    public private(set) var currentStepId: String
    private let journeyId: String
    private let steps: [String: Step]
    private let apiClient: ApiCalling
    private let emitToPage: (String, [String: Any]) -> Void
    public var onStepEnter: ((String) -> Void)?
    public var onTerminal: ((Step) -> Void)?
    public var onError: ((SdkErrorCode, Bool, String) -> Void)?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.hsbc.partnersdk.statemachine")
    
    public init(
        journeyId: String,
        steps: [String: Step],
        startStepId: String,
        apiClient: ApiCalling,
        emitToPage: @escaping (String, [String: Any]) -> Void
    ) {
        self.journeyId = journeyId
        self.steps = steps
        self.currentStepId = startStepId
        self.apiClient = apiClient
        self.emitToPage = emitToPage
        enter(stepId: startStepId, previous: nil)
    }
    
    /// Handles an event from the page/bridge.
    public func handleEvent(name: String, payload: [String: Any]) {
        queue.async {
            self.processEvent(name: name, payload: payload)
        }
    }
    
    private func processEvent(name: String, payload: [String: Any]) {
        guard let currentStep = steps[currentStepId] else { return }
        
        // Execute bindings first
        if let bindings = currentStep.bindings {
            for binding in bindings where binding.onEvent == name {
                Task {
                    await self.execute(binding: binding, eventPayload: payload, step: currentStep)
                }
            }
        }
        
        guard let transition = currentStep.on?[name] else { return }
        
        if let guardExpr = transition.guardExpr,
           evaluate(guardExpr: guardExpr, payload: payload) == false {
            return
        }
        
        if let emit = transition.emit {
            emitToPage(emit, [:])
        }
        
        if let next = transition.to {
            move(to: next)
        }
    }
    
    private func move(to stepId: String) {
        let previous = currentStepId
        currentStepId = stepId
        emitStepEvents(previous: previous, next: stepId)
        enter(stepId: stepId, previous: previous)
    }
    
    private func enter(stepId: String, previous: String?) {
        timer?.cancel()
        
        guard let step = steps[stepId] else { return }
        
        EventBus.shared.stepEnter(stepName: stepId, correlationId: SessionManager.shared.correlationId)
        SessionManager.shared.saveSnapshot(journeyId: journeyId, stepId: stepId)
        onStepEnter?(stepId)
        
        if step.type == .terminal {
            onTerminal?(step)
            return
        }
        
        if let timeout = step.timeoutMs {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .milliseconds(timeout))
            timer.setEventHandler { [weak self] in
                self?.processEvent(name: "timeout", payload: [:])
            }
            timer.resume()
            self.timer = timer
        }
    }
    
    private func emitStepEvents(previous: String?, next: String) {
        if let previous = previous {
            EventBus.shared.stepExit(stepName: previous, correlationId: SessionManager.shared.correlationId)
        }
    }
    
    // MARK: - Bindings
    
    private func execute(binding: Binding, eventPayload: [String: Any], step: Step) async {
        let body: [String: Any]?
        if let argsPath = binding.call.argsFrom {
            body = extract(path: argsPath, from: eventPayload) as? [String: Any]
        } else {
            body = nil
        }
        
        let headers = binding.call.headers ?? [:]
        do {
            let response = try await apiClient.call(
                operationId: binding.call.operationId,
                body: body,
                headers: headers,
                idempotencyKey: step.idempotencyKey
            )
            
            if let emit = binding.onSuccessEmit {
                emitToPage(emit, ["status": response.status])
            }
            SessionManager.shared.saveSnapshot(journeyId: journeyId, stepId: step.idempotencyKey ?? currentStepId)
        } catch {
            if let emit = binding.onErrorEmit {
                emitToPage(emit, ["error": String(describing: error)])
            }
            if let apiError = error as? ApiClientError {
                let mapped: SdkErrorCode
                let recoverable: Bool
                switch apiError {
                case .retryLimitExceeded(_, _, let code):
                    mapped = code
                    recoverable = code == .NET_TIMEOUT || code == .RATE_LIMITED
                case .httpError(_, _, let code):
                    mapped = code
                    recoverable = code == .NET_TIMEOUT || code == .RATE_LIMITED
                default:
                    mapped = .UNKNOWN
                    recoverable = false
                }
                onError?(mapped, recoverable, String(describing: error))
            }
        }
    }
    
    // MARK: - Guard evaluation
    
    private func evaluate(guardExpr: String, payload: [String: Any]) -> Bool {
        let context: [String: Any] = [
            "payload": payload,
            "session": [
                "resumeToken": SessionManager.shared.resumeToken as Any,
                "idempotencyKey": SessionManager.shared.idempotencyKey
            ]
        ]
        return ExpressionEvaluator(context: context).evaluate(expression: guardExpr)
    }
    
    private func extract(path: String, from dict: [String: Any]) -> Any? {
        let parts = path.split(separator: ".").map(String.init)
        var current: Any? = dict
        for part in parts {
            if let d = current as? [String: Any] {
                current = d[part]
            } else {
                return nil
            }
        }
        return current
    }
}

// MARK: - Tiny expression evaluator

private struct ExpressionEvaluator {
    let context: [String: Any]
    
    func evaluate(expression: String) -> Bool {
        let orParts = expression.components(separatedBy: "||")
        for part in orParts {
            let andParts = part.components(separatedBy: "&&")
            let andResult = andParts.allSatisfy { evaluateComparison($0.trimmingCharacters(in: .whitespaces)) }
            if andResult { return true }
        }
        return false
    }
    
    private func evaluateComparison(_ expr: String) -> Bool {
        let operators = ["==", "!=", ">=", "<=", ">", "<"]
        var opUsed: String?
        for op in operators where expr.contains(op) {
            opUsed = op
            break
        }
        guard let op = opUsed else { return false }
        let parts = expr.components(separatedBy: op)
        guard parts.count == 2 else { return false }
        
        let lhs = resolve(value: parts[0].trimmingCharacters(in: .whitespaces))
        let rhs = resolve(value: parts[1].trimmingCharacters(in: .whitespaces))
        
        switch op {
        case "==": return anyEqual(lhs, rhs)
        case "!=": return !anyEqual(lhs, rhs)
        case ">": return compare(lhs, rhs) == .orderedDescending
        case "<": return compare(lhs, rhs) == .orderedAscending
        case ">=": return compare(lhs, rhs) != .orderedAscending
        case "<=": return compare(lhs, rhs) != .orderedDescending
        default: return false
        }
    }
    
    private func resolve(value: String) -> Any? {
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        if let intVal = Int(value) { return intVal }
        if let doubleVal = Double(value) { return doubleVal }
        
        // Dotted lookup
        let parts = value.split(separator: ".").map(String.init)
        var current: Any? = context
        for part in parts {
            if let d = current as? [String: Any] {
                current = d[part]
            } else {
                return nil
            }
        }
        return current
    }
    
    private func anyEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case let (l as String, r as String): return l == r
        case let (l as Int, r as Int): return l == r
        case let (l as Double, r as Double): return l == r
        case let (l as Int, r as Double): return Double(l) == r
        case let (l as Double, r as Int): return l == Double(r)
        case let (l as Bool, r as Bool): return l == r
        default: return false
        }
    }
    
    private func compare(_ lhs: Any?, _ rhs: Any?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (l as Int, r as Int):
            return l == r ? .orderedSame : (l < r ? .orderedAscending : .orderedDescending)
        case let (l as Double, r as Double):
            return l == r ? .orderedSame : (l < r ? .orderedAscending : .orderedDescending)
        case let (l as Int, r as Double):
            return Double(l) == r ? .orderedSame : (Double(l) < r ? .orderedAscending : .orderedDescending)
        case let (l as Double, r as Int):
            return l == Double(r) ? .orderedSame : (l < Double(r) ? .orderedAscending : .orderedDescending)
        case let (l as String, r as String):
            return l == r ? .orderedSame : (l < r ? .orderedAscending : .orderedDescending)
        default:
            return .orderedSame
        }
    }
}
