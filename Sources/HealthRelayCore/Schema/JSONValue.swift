import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Decimal)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}

struct DynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

func decodeUnknownFields(
    from decoder: Decoder,
    excluding knownKeys: Set<String>
) throws -> [String: JSONValue] {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    var result: [String: JSONValue] = [:]
    for key in container.allKeys where !knownKeys.contains(key.stringValue) {
        result[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
    }
    return result
}

func encodeUnknownFields(
    _ fields: [String: JSONValue],
    to encoder: Encoder,
    excluding knownKeys: Set<String>
) throws {
    var container = encoder.container(keyedBy: DynamicCodingKey.self)
    for key in fields.keys.sorted() where !knownKeys.contains(key) {
        try container.encode(fields[key], forKey: DynamicCodingKey(key))
    }
}

func mergedUnknownFields(
    prior: [String: JSONValue],
    current: [String: JSONValue]
) -> [String: JSONValue] {
    prior.merging(current) { _, currentValue in currentValue }
}
