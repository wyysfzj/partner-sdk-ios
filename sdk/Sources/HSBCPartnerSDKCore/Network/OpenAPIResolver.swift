import Foundation

/// Errors that can occur while resolving OpenAPI operations.
public enum OpenAPIResolverError: Error {
    case invalidDocument
    case unknownOperationId(String)
    case invalidBody
    case invalidURL
}

/// Resolves OpenAPI operationId values to HTTP method and path pairs.
public struct OpenAPIResolver {
    
    public struct Operation {
        public let method: String
        public let path: String
    }
    
    private let operations: [String: Operation]
    
    /// Creates a resolver from a JSON OpenAPI 3 document.
    /// - Parameter openAPIData: Raw JSON data representing the OpenAPI document.
    public init(openAPIData: Data) throws {
        operations = try OpenAPIResolver.parseOperations(from: openAPIData)
    }
    
    /// Returns the operation for the given operationId.
    /// - Parameter operationId: The operation identifier to resolve.
    public func resolve(operationId: String) -> Operation? {
        operations[operationId]
    }
    
    /// Returns true if the given operationId exists.
    public func hasOperationId(_ operationId: String) -> Bool {
        operations[operationId] != nil
    }
    
    /// Validates that all operationIds referenced in the manifest exist in the OpenAPI document.
    public func validateOperationIds(manifest: Manifest) throws {
        for (_, step) in manifest.steps {
            if let bindings = step.bindings {
                for binding in bindings {
                    if hasOperationId(binding.call.operationId) == false {
                        throw OpenAPIResolverError.invalidDocument
                    }
                }
            }
        }
    }
    
    /// Builds a URLRequest for a resolved operation.
    /// - Parameters:
    ///   - baseURL: Base endpoint for the API.
    ///   - operationId: Operation identifier present in the OpenAPI document.
    ///   - body: Optional JSON body.
    ///   - headers: Additional headers to attach.
    public func makeRequest(
        baseURL: URL,
        operationId: String,
        body: [String: Any]?,
        headers: [String: String] = [:]
    ) throws -> URLRequest {
        guard let operation = resolve(operationId: operationId) else {
            throw OpenAPIResolverError.unknownOperationId(operationId)
        }
        return try OpenAPIResolver.buildRequest(
            baseURL: baseURL,
            operation: operation,
            body: body,
            headers: headers
        )
    }
    
    /// Builds a URLRequest from the given operation.
    /// - Parameters:
    ///   - baseURL: Base endpoint for the API.
    ///   - operation: The resolved operation (method/path).
    ///   - body: Optional JSON body.
    ///   - headers: Additional headers to attach.
    public static func buildRequest(
        baseURL: URL,
        operation: Operation,
        body: [String: Any]?,
        headers: [String: String] = [:]
    ) throws -> URLRequest {
        let normalizedPath = normalizePath(base: baseURL.path, operationPath: operation.path)
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw OpenAPIResolverError.invalidURL
        }
        components.path = normalizedPath
        
        guard let url = components.url else {
            throw OpenAPIResolverError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = operation.method.uppercased()
        
        var allHeaders = headers
        if let body {
            guard JSONSerialization.isValidJSONObject(body) else {
                throw OpenAPIResolverError.invalidBody
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            allHeaders["Content-Type"] = allHeaders["Content-Type"] ?? "application/json"
        }
        allHeaders["Accept"] = allHeaders["Accept"] ?? "application/json"
        allHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        return request
    }
    
    // MARK: - Parsing
    
    private static func parseOperations(from data: Data) throws -> [String: Operation] {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let dict = jsonObject as? [String: Any],
              let paths = dict["paths"] as? [String: Any] else {
            throw OpenAPIResolverError.invalidDocument
        }
        
        var map: [String: Operation] = [:]
        
        for (path, value) in paths {
            guard let methods = value as? [String: Any] else { continue }
            for (method, opValue) in methods {
                guard let opDict = opValue as? [String: Any],
                      let operationId = opDict["operationId"] as? String else {
                    continue
                }
                map[operationId] = Operation(method: method.uppercased(), path: path)
            }
        }
        
        if map.isEmpty {
            throw OpenAPIResolverError.invalidDocument
        }
        return map
    }
    
    private static func normalizePath(base: String, operationPath: String) -> String {
        let trimmedBase = base == "/" ? "" : base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedOp = operationPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let joined = [trimmedBase, trimmedOp].filter { !$0.isEmpty }.joined(separator: "/")
        return "/\(joined)"
    }
}
