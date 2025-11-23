import XCTest
@testable import HSBCPartnerSDKCore

final class StateMachineTests: XCTestCase {
    
    func testTransitionsAndTimeout() throws {
        let step1 = Step(
            type: .web,
            url: nil,
            plugin: nil,
            params: nil,
            timeoutMs: nil,
            bindings: nil,
            on: ["next": Transition(to: "step2", emit: nil, guardExpr: nil)],
            result: nil,
            bridgeAllow: nil,
            idempotencyKey: nil
        )
        let step2 = Step(
            type: .web,
            url: nil,
            plugin: nil,
            params: nil,
            timeoutMs: 50,
            bindings: nil,
            on: ["timeout": Transition(to: "step3", emit: nil, guardExpr: nil)],
            result: nil,
            bridgeAllow: nil,
            idempotencyKey: nil
        )
        let step3 = Step(
            type: .terminal,
            url: nil,
            plugin: nil,
            params: nil,
            timeoutMs: nil,
            bindings: nil,
            on: nil,
            result: nil,
            bridgeAllow: nil,
            idempotencyKey: nil
        )
        
        let emitter = EventCollector()
        let api = StubApiClient()
        let sm = StateMachine(
            journeyId: "journey",
            steps: ["step1": step1, "step2": step2, "step3": step3],
            startStepId: "step1",
            apiClient: api
        ) { name, payload in
            emitter.add(name: name, payload: payload)
        }
        
        sm.handleEvent(name: "next", payload: [:])
        let step2Entered = expectation(description: "moved to step2")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            if sm.currentStepId == "step2" {
                step2Entered.fulfill()
            }
        }
        wait(for: [step2Entered], timeout: 1.0)
        
        let step3Entered = expectation(description: "timeout moved to step3")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.12) {
            if sm.currentStepId == "step3" {
                step3Entered.fulfill()
            }
        }
        wait(for: [step3Entered], timeout: 1.0)
    }
    
    func testGuardExpressionBlocksAndAllows() throws {
        let guarded = Step(
            type: .web,
            url: nil,
            plugin: nil,
            params: nil,
            timeoutMs: nil,
            bindings: nil,
            on: [
                "go": Transition(to: "dest", emit: nil, guardExpr: "payload.value == 2")
            ],
            result: nil,
            bridgeAllow: nil,
            idempotencyKey: nil
        )
        let dest = Step(type: .terminal, url: nil, plugin: nil, params: nil, timeoutMs: nil, bindings: nil, on: nil, result: nil, bridgeAllow: nil, idempotencyKey: nil)
        let api = StubApiClient()
        let emitter = EventCollector()
        let sm = StateMachine(
            journeyId: "journey",
            steps: ["g": guarded, "dest": dest],
            startStepId: "g",
            apiClient: api
        ) { name, payload in
            emitter.add(name: name, payload: payload)
        }
        sm.handleEvent(name: "go", payload: ["value": 1])
        XCTAssertEqual(sm.currentStepId, "g") // blocked
        sm.handleEvent(name: "go", payload: ["value": 2])
        let reached = expectation(description: "reached dest")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            if sm.currentStepId == "dest" {
                reached.fulfill()
            }
        }
        wait(for: [reached], timeout: 1.0)
    }
    
    func testBindingCallsApiClientAndEmits() throws {
        let binding = Binding(
            onEvent: "submit",
            call: BindingCall(operationId: "op1", argsFrom: "data", headers: [:]),
            onSuccessEmit: "on_success",
            onErrorEmit: "on_error"
        )
        
        let step = Step(
            type: .web,
            url: nil,
            plugin: nil,
            params: nil,
            timeoutMs: nil,
            bindings: [binding],
            on: nil,
            result: nil,
            bridgeAllow: nil,
            idempotencyKey: "idem-1"
        )
        
        let api = StubApiClient()
        api.result = .success((status: 200, headers: [:], body: Data()))
        let emitter = EventCollector()
        let sm = StateMachine(
            journeyId: "journey",
            steps: ["s": step],
            startStepId: "s",
            apiClient: api
        ) { name, payload in
            emitter.add(name: name, payload: payload)
        }
        
        sm.handleEvent(name: "submit", payload: ["data": ["foo": "bar"]])
        
        let emitted = expectation(description: "success emitted")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            if emitter.contains(name: "on_success") {
                emitted.fulfill()
            }
        }
        wait(for: [emitted], timeout: 1.0)
        XCTAssertEqual(api.lastIdempotencyKey, "idem-1")
    }
}

// MARK: - Test helpers

private final class StubApiClient: ApiCalling {
    enum Result {
        case success((status: Int, headers: [AnyHashable: Any], body: Data))
        case failure(Error)
    }
    
    var result: Result = .success((status: 200, headers: [:], body: Data()))
    var lastBody: [String: Any]?
    var lastIdempotencyKey: String?
    
    func call(operationId: String, body: [String : Any]?, headers: [String : String], idempotencyKey: String?) async throws -> (status: Int, headers: [AnyHashable : Any], body: Data) {
        lastBody = body
        lastIdempotencyKey = idempotencyKey
        switch result {
        case .success(let tuple): return tuple
        case .failure(let error): throw error
        }
    }
}

private final class EventCollector {
    private var events: [(String, [String: Any])] = []
    private let queue = DispatchQueue(label: "collector")
    
    func add(name: String, payload: [String: Any]) {
        queue.sync {
            events.append((name, payload))
        }
    }
    
    func contains(name: String) -> Bool {
        queue.sync { events.contains { $0.0 == name } }
    }
}
