import Foundation

// MARK: - Manifest

/// Represents the Journey Manifest v1.1.
public struct Manifest: Codable {
    public let manifestVersion: String
    public let minSdk: String
    public let journeyId: String
    public let oapiBundle: URL
    public let locales: [String]?
    public let startStep: String
    public let headers: [String: String]
    public let security: Security
    public let resumePolicy: ResumePolicy?
    public let steps: [String: Step]
    public let signature: String
}

// MARK: - Security

public struct Security: Codable {
    public let allowedOrigins: [URL]
    public let pinning: Bool
    public let attestation: [String: Bool]?
    public let requireHandshake: Bool
}

// MARK: - ResumePolicy

public struct ResumePolicy: Codable {
    public let snapshotOn: [String]
}

// MARK: - Step

public struct Step: Codable {
    public let type: StepType
    public let url: URL?
    public let plugin: String?
    public let params: [String: AnyCodable]?
    public let timeoutMs: Int?
    public let bindings: [Binding]?
    public let on: [String: Transition]?
    public let result: [String: AnyCodable]?
    public let bridgeAllow: [String]?
    public let idempotencyKey: String?
}

public enum StepType: String, Codable {
    case web
    case native
    case server
    case terminal
}

// MARK: - Binding

public struct Binding: Codable {
    public let onEvent: String
    public let call: BindingCall
    public let onSuccessEmit: String?
    public let onErrorEmit: String?
}

public struct BindingCall: Codable {
    public let operationId: String
    public let argsFrom: String?
    public let headers: [String: String]?
}

// MARK: - Transition

public struct Transition: Codable {
    public let to: String?
    public let emit: BridgeEvent?
    public let guardExpr: String?
    
    private enum CodingKeys: String, CodingKey {
        case to
        case emit
        case guardExpr = "guard"
    }
}

/// Event to be emitted during a transition.
/// Currently defined as a String alias, but could be expanded to a struct if needed.
public typealias BridgeEvent = String

// MARK: - AnyCodable

/// A type-erased Codable value that can hold any JSON-compatible data.
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            value = arrayVal.map { $0.value }
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let stringVal = value as? String {
            try container.encode(stringVal)
        } else if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else if let arrayVal = value as? [Any] {
            try container.encode(arrayVal.map { AnyCodable($0) })
        } else if let dictVal = value as? [String: Any] {
            try container.encode(dictVal.mapValues { AnyCodable($0) })
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}
