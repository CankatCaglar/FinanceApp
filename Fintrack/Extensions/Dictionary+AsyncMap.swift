import Foundation

extension Dictionary {
    func asyncCompactMap<T>(_ transform: (Key, Value) async throws -> T?) async rethrows -> [T] {
        var results = [T]()
        for (key, value) in self {
            if let transformed = try await transform(key, value) {
                results.append(transformed)
            }
        }
        return results
    }
} 