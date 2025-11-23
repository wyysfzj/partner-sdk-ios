import Foundation

/// Protocol that represents a pluggable capability the Bridge can dispatch to.
public protocol JourneyPlugin {
    var name: String { get }
    func canHandle(_ method: String) -> Bool
    func handle(_ method: String, params: [String: Any]) async throws -> [String: Any]
}

/// Registry that keeps plugins discoverable for Bridge dispatch.
public final class PluginRegistry {
    public static let shared = PluginRegistry()
    private var plugins: [JourneyPlugin] = []
    private let queue = DispatchQueue(label: "com.hsbc.partnersdk.pluginregistry")

    private init() {}

    public func register(_ plugin: JourneyPlugin) {
        queue.sync {
            plugins.removeAll { $0.name == plugin.name }
            plugins.append(plugin)
        }
    }

    public func resolve(method: String) -> JourneyPlugin? {
        queue.sync {
            plugins.first { $0.canHandle(method) }
        }
    }
}
