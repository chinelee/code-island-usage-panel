import Foundation
import Combine

struct OpenTokenHourlyRecord: Decodable, Identifiable {
    let hourUTC: String
    let tool: String
    let model: String
    let input: Int64
    let output: Int64
    let cacheRead: Int64
    let cacheWrite: Int64

    enum CodingKeys: String, CodingKey {
        case hourUTC = "hour_utc"
        case tool, model, input, output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
    }

    var id: String { "\(hourUTC)|\(tool)|\(model)" }
    var totalTokens: Int64 { input + output + cacheRead + cacheWrite }
}

struct OpenTokenHourBucket: Identifiable {
    let hour: Date
    let modelTokens: [String: Int64]

    var id: Date { hour }
    var total: Int64 { modelTokens.values.reduce(0, +) }
}

struct OpenTokenModelUsage: Identifiable {
    let model: String
    let tool: String
    let tokens: Int64

    var id: String { "\(tool)|\(model)" }
}

struct OpenTokenToolUsage: Identifiable {
    let tool: String
    let tokens: Int64

    var id: String { tool }
}

struct OpenTokenBreakdown {
    let input: Int64
    let output: Int64
    let cacheRead: Int64
    let cacheWrite: Int64

    var total: Int64 { input + output + cacheRead + cacheWrite }
}

enum OpenTokenPayloadParser {
    private struct V2Payload: Decodable {
        let v2Hourly: [OpenTokenHourlyRecord]

        enum CodingKeys: String, CodingKey {
            case v2Hourly = "v2_hourly"
        }
    }

    static func parse(_ data: Data) throws -> [OpenTokenHourlyRecord] {
        for object in splitTopLevelJSONObjects(data) {
            if let payload = try? JSONDecoder().decode(V2Payload.self, from: object) {
                return payload.v2Hourly
            }
        }
        throw NSError(
            domain: "CodeIsland.OpenToken",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "OpenToken did not return hourly usage data"]
        )
    }

    /// OpenToken prints the legacy payload and v2 payload consecutively. Split
    /// the stream without assuming whitespace or line boundaries between them.
    static func splitTopLevelJSONObjects(_ data: Data) -> [Data] {
        let bytes = Array(data)
        var result: [Data] = []
        var start: Int?
        var depth = 0
        var inString = false
        var escaped = false

        for (index, byte) in bytes.enumerated() {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
                continue
            }

            if byte == 0x22 {
                inString = true
            } else if byte == 0x7B {
                if depth == 0 { start = index }
                depth += 1
            } else if byte == 0x7D, depth > 0 {
                depth -= 1
                if depth == 0, let objectStart = start {
                    result.append(Data(bytes[objectStart...index]))
                    start = nil
                }
            }
        }
        return result
    }

}

@MainActor
final class OpenTokenUsageStore: ObservableObject {
    @Published private(set) var records: [OpenTokenHourlyRecord] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshedAt: Date?

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 5 * 60

    init() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    var totalTokens: Int64 { hourBuckets.reduce(0) { $0 + $1.total } }

    private var records24Hours: [OpenTokenHourlyRecord] {
        let calendar = Calendar(identifier: .gregorian)
        let nowHour = calendar.dateInterval(of: .hour, for: Date())?.start ?? Date()
        let start = calendar.date(byAdding: .hour, value: -23, to: nowHour) ?? nowHour
        return records.filter {
            guard let date = Self.date(fromHourUTC: $0.hourUTC) else { return false }
            return date >= start && date <= nowHour
        }
    }

    var toolUsage24Hours: [OpenTokenToolUsage] {
        var grouped: [String: Int64] = [:]
        for record in records24Hours {
            grouped[Self.normalizedTool(record.tool), default: 0] += record.totalTokens
        }
        return ["codex", "claude", "workbuddy"].map {
            OpenTokenToolUsage(tool: $0, tokens: grouped[$0] ?? 0)
        }
    }

    var tokenBreakdown24Hours: OpenTokenBreakdown {
        records24Hours.reduce(OpenTokenBreakdown(input: 0, output: 0, cacheRead: 0, cacheWrite: 0)) {
            OpenTokenBreakdown(
                input: $0.input + $1.input,
                output: $0.output + $1.output,
                cacheRead: $0.cacheRead + $1.cacheRead,
                cacheWrite: $0.cacheWrite + $1.cacheWrite
            )
        }
    }

    var latestHourModelUsage: [OpenTokenModelUsage] {
        let datedRecords = records.compactMap { record -> (Date, OpenTokenHourlyRecord)? in
            guard let date = Self.date(fromHourUTC: record.hourUTC) else { return nil }
            return (date, record)
        }
        guard let latestHour = datedRecords.map(\.0).max() else { return [] }
        var grouped: [String: (tool: String, tokens: Int64)] = [:]
        for (date, record) in datedRecords where date == latestHour {
            let key = record.model
            let existing = grouped[key] ?? (record.tool, 0)
            grouped[key] = (existing.tool, existing.tokens + record.totalTokens)
        }
        return grouped.map { OpenTokenModelUsage(model: $0.key, tool: $0.value.tool, tokens: $0.value.tokens) }
            .sorted { $0.tokens > $1.tokens }
    }

    var latestHourTokens: Int64 {
        latestHourModelUsage.reduce(0) { $0 + $1.tokens }
    }

    var modelUsage24Hours: [OpenTokenModelUsage] {
        var grouped: [String: Int64] = [:]
        for record in records24Hours {
            grouped[record.model, default: 0] += record.totalTokens
        }
        return grouped.map { OpenTokenModelUsage(model: $0.key, tool: tool(forModel: $0.key), tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }
    }

    private func tool(forModel model: String) -> String {
        records.first(where: { $0.model == model })?.tool ?? "unknown"
    }

    private static func normalizedTool(_ value: String) -> String {
        switch value.lowercased() {
        case "claude", "claude-code": return "claude"
        case "workbuddy", "codebuddy": return "workbuddy"
        default: return value.lowercased()
        }
    }

    var hourBuckets: [OpenTokenHourBucket] {
        let calendar = Calendar(identifier: .gregorian)
        let nowHour = calendar.dateInterval(of: .hour, for: Date())?.start ?? Date()
        var grouped: [Date: [String: Int64]] = [:]
        for record in records {
            guard let date = Self.date(fromHourUTC: record.hourUTC) else { continue }
            let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
            var models = grouped[hour] ?? [:]
            models[record.model, default: 0] += record.totalTokens
            grouped[hour] = models
        }

        return (0..<24).compactMap { offset in
            guard let hour = calendar.date(byAdding: .hour, value: offset - 23, to: nowHour) else { return nil }
            return OpenTokenHourBucket(hour: hour, modelTokens: grouped[hour] ?? [:])
        }
    }

    private static func date(fromHourUTC value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH"
        return formatter.date(from: value)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let loaded = try await Self.loadRecords()
            records = loaded.filter {
                ["codex", "claude", "claude-code", "workbuddy", "codebuddy"].contains($0.tool.lowercased())
            }
            errorMessage = nil
            lastRefreshedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private nonisolated static func loadRecords() async throws -> [OpenTokenHourlyRecord] {
        try await Task.detached(priority: .utility) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let candidates = [
                home.appendingPathComponent(".local/bin/opentoken").path,
                "/opt/homebrew/bin/opentoken",
                "/usr/local/bin/opentoken",
            ]
            guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                throw NSError(
                    domain: "CodeIsland.OpenToken",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "OpenToken is not installed"]
                )
            }

            let startDate = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
            let dayFormatter = DateFormatter()
            dayFormatter.locale = Locale(identifier: "en_US_POSIX")
            dayFormatter.dateFormat = "yyyy-MM-dd"

            let process = Process()
            let errors = Pipe()
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("code-island-opentoken-\(UUID().uuidString).json")
            guard FileManager.default.createFile(
                atPath: outputURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw NSError(
                    domain: "CodeIsland.OpenToken",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Could not create a private OpenToken cache file"]
                )
            }
            let outputHandle = try FileHandle(forWritingTo: outputURL)
            defer {
                try? outputHandle.close()
                try? FileManager.default.removeItem(at: outputURL)
            }
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["upload", "--dry-run", "--v2", "--full", "--since", dayFormatter.string(from: startDate)]
            process.standardOutput = outputHandle
            process.standardError = errors
            try process.run()
            process.waitUntilExit()
            try outputHandle.synchronize()
            let outputData = try Data(contentsOf: outputURL)
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw NSError(
                    domain: "CodeIsland.OpenToken",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "OpenToken exited with an error"]
                )
            }
            return try OpenTokenPayloadParser.parse(outputData)
        }.value
    }
}
