import Foundation

/// A small value bridge matching Convex's JSON-like argument surface. The
/// real ConvexMobile adapter can convert `foundationValue` into the dictionary
/// accepted by `ConvexClient.mutation`, while tests and offline builds use the
/// unconfigured transport below without importing a package or needing a URL.
nonisolated enum CloudJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([CloudJSONValue])
    case object([String: CloudJSONValue])

    var foundationValue: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .null: NSNull()
        case .array(let values): values.map(\.foundationValue)
        case .object(let values): values.mapValues(\.foundationValue)
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, value }
    private enum Kind: String, Codable { case string, number, bool, null, array, object }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .string: self = .string(try container.decode(String.self, forKey: .value))
        case .number: self = .number(try container.decode(Double.self, forKey: .value))
        case .bool: self = .bool(try container.decode(Bool.self, forKey: .value))
        case .null: self = .null
        case .array: self = .array(try container.decode([CloudJSONValue].self, forKey: .value))
        case .object: self = .object(try container.decode([String: CloudJSONValue].self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .number(let value):
            try container.encode(Kind.number, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(Kind.bool, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .null:
            try container.encode(Kind.null, forKey: .kind)
        case .array(let values):
            try container.encode(Kind.array, forKey: .kind)
            try container.encode(values, forKey: .value)
        case .object(let values):
            try container.encode(Kind.object, forKey: .kind)
            try container.encode(values, forKey: .value)
        }
    }
}

typealias CloudArguments = [String: CloudJSONValue]

nonisolated struct CloudMutationAck: Codable, Equatable, Sendable {
    let ok: Bool
    let operation: String?
    let entityId: String?
    let deduplicated: Bool?
}

nonisolated struct CloudEnsureUserResponse: Codable, Equatable, Sendable {
    let userId: String
    let profileId: String?
    let created: Bool
}

/// This protocol intentionally mirrors the two Convex operations the app
/// needs. A future adapter can wrap `ConvexMobile.ConvexClient` or
/// `ConvexClientWithAuth` without leaking that package through the domain or
/// tests.
protocol ConvexTransport: Sendable {
    @MainActor
    func query<Value: Decodable & Sendable>(
        _ function: String,
        arguments: CloudArguments,
        as type: Value.Type
    ) async throws -> Value

    @MainActor
    func mutation<Value: Decodable & Sendable>(
        _ function: String,
        arguments: CloudArguments,
        as type: Value.Type
    ) async throws -> Value
}

nonisolated struct UnconfiguredConvexTransport: ConvexTransport {
    init() {}

    @MainActor
    func query<Value: Decodable & Sendable>(
        _ function: String,
        arguments: CloudArguments,
        as type: Value.Type
    ) async throws -> Value {
        throw CloudSyncError.notConfigured
    }

    @MainActor
    func mutation<Value: Decodable & Sendable>(
        _ function: String,
        arguments: CloudArguments,
        as type: Value.Type
    ) async throws -> Value {
        throw CloudSyncError.notConfigured
    }
}

protocol CloudRemote: Sendable {
    func apply(_ operation: CloudSyncOperation, mutationID: String) async throws -> CloudMutationAck
}

/// High-level Convex client abstraction. It is safe to construct in the app
/// before the package dependency, auth provider or deployment URL exists.
/// `UnconfiguredConvexTransport` makes that state explicit instead of
/// silently dropping local outbox entries.
actor ConvexCloudClient: CloudRemote {
    private let transport: any ConvexTransport

    init(transport: any ConvexTransport = UnconfiguredConvexTransport()) {
        self.transport = transport
    }

    func ensureCurrentUser() async throws -> CloudEnsureUserResponse {
        try await transport.mutation(
            "users:ensureCurrentUser",
            arguments: [:],
            as: CloudEnsureUserResponse.self
        )
    }

    func apply(_ operation: CloudSyncOperation, mutationID: String) async throws -> CloudMutationAck {
        let arguments = try operation.arguments(mutationID: mutationID)
        switch operation.kind {
        case .deleteAccount:
            // deleteMyAccount returns a deletion result rather than the normal
            // receipt ack; the outbox only needs a successful response.
            let result: CloudDeletionResponse = try await transport.mutation(
                operation.functionName,
                arguments: arguments,
                as: CloudDeletionResponse.self
            )
            return CloudMutationAck(
                ok: result.deleted,
                operation: operation.kind.rawValue,
                entityId: nil,
                deduplicated: result.alreadyDeleted
            )
        default:
            return try await transport.mutation(
                operation.functionName,
                arguments: arguments,
                as: CloudMutationAck.self
            )
        }
    }
}

private nonisolated struct CloudDeletionResponse: Codable, Sendable {
    let deleted: Bool
    let alreadyDeleted: Bool
}
