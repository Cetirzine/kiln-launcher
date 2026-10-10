import Foundation

/// 轻量 JSON 值类型，便于处理版本 JSON 中结构不固定的字段（arguments、rules 等）
package enum JSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    package init(data: Data) throws {
        self = JSON(any: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    package init(any: Any) {
        switch any {
        case let v as NSNumber:
            if CFGetTypeID(v) == CFBooleanGetTypeID() { self = .bool(v.boolValue) } else { self = .number(v.doubleValue) }
        case let v as String: self = .string(v)
        case let v as [Any]: self = .array(v.map(JSON.init(any:)))
        case let v as [String: Any]: self = .object(v.mapValues(JSON.init(any:)))
        default: self = .null
        }
    }

    package var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? Int(n) as Any : n
        case .string(let s): return s
        case .array(let a): return a.map(\.any)
        case .object(let o): return o.mapValues(\.any)
        }
    }

    package func data(pretty: Bool = true) -> Data {
        (try? JSONSerialization.data(withJSONObject: any, options: pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes])) ?? Data()
    }

    package subscript(key: String) -> JSON {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    package subscript(index: Int) -> JSON {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return .null
    }

    package var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return String(b)
        default: return nil
        }
    }
    package var int: Int? { if case .number(let n) = self { return Int(n) }; return string.flatMap { Int($0) } }
    package var double: Double? { if case .number(let n) = self { return n }; return nil }
    package var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    package var array: [JSON] { if case .array(let a) = self { return a }; return [] }
    package var object: [String: JSON] { if case .object(let o) = self { return o }; return [:] }
    package var isNull: Bool { if case .null = self { return true }; return false }
    package var exists: Bool { !isNull }
}
