import Foundation
import Combine

@MainActor
final class SessionTokenUsageStore: ObservableObject {
    @Published private(set) var totals: [String: Int64] = [:]
    @Published private(set) var isRefreshing = false

    private struct Descriptor: Sendable {
        let id: String
        let source: String
    }

    func tokens(for sessionID: String) -> Int64? {
        totals[sessionID]
    }

    func refresh(sessions: [Session]) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let descriptors = sessions.map { Descriptor(id: $0.id, source: $0.source) }
        totals = await Task.detached(priority: .utility) {
            var result: [String: Int64] = [:]
            for descriptor in descriptors {
                if let total = Self.readTokens(for: descriptor) {
                    result[descriptor.id] = total
                }
            }
            return result
        }.value
    }

    private nonisolated static func readTokens(for descriptor: Descriptor) -> Int64? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch descriptor.source.lowercased() {
        case "claude", "claude-code":
            let root = home.appendingPathComponent(".claude/projects")
            guard let file = findFile(containing: descriptor.id, under: root) else { return nil }
            return readClaudeTokens(file)
        case "codex":
            let root = home.appendingPathComponent(".codex/sessions")
            guard let file = findFile(containing: descriptor.id, under: root) else { return nil }
            return readCodexTokens(file)
        default:
            return nil
        }
    }

    private nonisolated static func findFile(containing sessionID: String, under root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            if url.lastPathComponent.contains(sessionID) { return url }
        }
        return nil
    }

    private nonisolated static func readClaudeTokens(_ file: URL) -> Int64? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return claudeTokenTotal(from: data)
    }

    nonisolated static func claudeTokenTotal(from data: Data) -> Int64? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var total: Int64 = 0
        var found = false
        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }
            found = true
            total += integer(usage["input_tokens"])
            total += integer(usage["output_tokens"])
            total += integer(usage["cache_read_input_tokens"])
            total += integer(usage["cache_creation_input_tokens"])
        }
        return found ? total : nil
    }

    private nonisolated static func readCodexTokens(_ file: URL) -> Int64? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return codexTokenTotal(from: data)
    }

    nonisolated static func codexTokenTotal(from data: Data) -> Int64? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var maximum: Int64?
        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let info = payload["info"] as? [String: Any],
                  let usage = info["total_token_usage"] as? [String: Any] else { continue }
            let value = integer(usage["total_tokens"])
            maximum = max(maximum ?? 0, value)
        }
        return maximum
    }

    private nonisolated static func integer(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) ?? 0 }
        return 0
    }
}
