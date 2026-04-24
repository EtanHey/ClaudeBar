import Foundation
import Domain

/// Loads local Codex analytics from `@ccusage/codex` and caches the last good report on disk.
public struct CodexLocalAnalyticsAnalyzer: CodexLocalAnalyticsAnalyzing, Sendable {
    private let cliExecutor: any CLIExecutor
    private let codexDirectory: URL
    private let cacheFileURL: URL
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let cacheTTL: TimeInterval

    public init(
        cliExecutor: (any CLIExecutor)? = nil,
        codexDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex", isDirectory: true),
        cacheFileURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claudebar/cache/codex-local-analytics.json"),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        cacheTTL: TimeInterval = 300
    ) {
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
        self.codexDirectory = codexDirectory
        self.cacheFileURL = cacheFileURL
        self.calendar = calendar
        self.now = now
        self.cacheTTL = cacheTTL
    }

    public func cachedReport() async -> CodexLocalAnalyticsReport? {
        readCache()?.report
    }

    public func refresh(policy: CodexLocalAnalyticsRefreshPolicy) async throws -> CodexLocalAnalyticsReport? {
        let cache = readCache()
        let newestSessionModifiedAt = newestSessionModifiedAt()
        let timezoneIdentifier = calendar.timeZone.identifier
        let preferredRunner = selectRunner()

        if policy == .ifNeeded,
           let cache,
           !isStale(
               cache: cache,
               newestSessionModifiedAt: newestSessionModifiedAt,
               timezoneIdentifier: timezoneIdentifier,
               preferredRunner: preferredRunner?.rawValue
           ) {
            return cache.report
        }

        guard let runner = preferredRunner else {
            return cache?.report
        }

        do {
            let report = try loadReport(using: runner)
            try writeCache(
                CachedReport(
                    generatedAt: now(),
                    newestSessionModifiedAt: newestSessionModifiedAt,
                    timezoneIdentifier: timezoneIdentifier,
                    runner: runner.rawValue,
                    report: report
                )
            )
            return report.hasContent ? report : nil
        } catch {
            if let cache {
                return cache.report
            }
            throw error
        }
    }

    // MARK: - Private

    private func selectRunner() -> Runner? {
        if cliExecutor.locate(Runner.bunx.rawValue) != nil {
            return .bunx
        }
        if cliExecutor.locate(Runner.npx.rawValue) != nil {
            return .npx
        }
        return nil
    }

    private func loadReport(using preferredRunner: Runner) throws -> CodexLocalAnalyticsReport {
        let runners: [Runner]
        switch preferredRunner {
        case .bunx:
            runners = [.bunx, .npx]
        case .npx:
            runners = [.npx]
        }

        var lastError: Error?
        for runner in runners where cliExecutor.locate(runner.rawValue) != nil {
            do {
                let dailyOutput = try execute(command: "daily", runner: runner)
                let monthlyOutput = try execute(command: "monthly", runner: runner)
                let sessionOutput = try execute(command: "session", runner: runner)
                return try parseReport(daily: dailyOutput, monthly: monthlyOutput, session: sessionOutput)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? ProbeError.executionFailed("Could not run @ccusage/codex")
    }

    private func execute(command: String, runner: Runner) throws -> String {
        let result = try cliExecutor.execute(
            binary: runner.rawValue,
            args: runner.arguments(for: command, timezoneIdentifier: calendar.timeZone.identifier),
            input: nil,
            timeout: 30,
            workingDirectory: nil,
            autoResponses: [:]
        )

        guard result.exitCode == 0 else {
            throw ProbeError.executionFailed("@ccusage/codex \(command) failed with exit code \(result.exitCode)")
        }

        return result.output
    }

    private func parseReport(daily: String, monthly: String, session: String) throws -> CodexLocalAnalyticsReport {
        let decoder = JSONDecoder()
        let dailyPayload = try decoder.decode(DailyPayload.self, from: Data(daily.utf8))
        let monthlyPayload = try decoder.decode(MonthlyPayload.self, from: Data(monthly.utf8))
        let sessionPayload = try decoder.decode(SessionPayload.self, from: Data(session.utf8))

        let today = dailyPayload.daily.last.map {
            CodexLocalAnalyticsSlice(
                costUSD: Decimal($0.costUSD),
                totalTokens: $0.totalTokens,
                cachedInputTokens: $0.cachedInputTokens,
                reasoningOutputTokens: $0.reasoningOutputTokens,
                referenceLabel: $0.date
            )
        } ?? .empty(referenceLabel: "Today")

        let thisMonth = monthlyPayload.monthly.last.map {
            CodexLocalAnalyticsSlice(
                costUSD: Decimal($0.costUSD),
                totalTokens: $0.totalTokens,
                cachedInputTokens: $0.cachedInputTokens,
                reasoningOutputTokens: $0.reasoningOutputTokens,
                referenceLabel: $0.month
            )
        } ?? .empty(referenceLabel: "This Month")

        let latestSession = sessionPayload.sessions.last.map {
            CodexLocalAnalyticsSlice(
                costUSD: Decimal($0.costUSD),
                totalTokens: $0.totalTokens,
                cachedInputTokens: $0.cachedInputTokens,
                reasoningOutputTokens: $0.reasoningOutputTokens,
                referenceLabel: $0.lastActivity
            )
        } ?? .empty(referenceLabel: "Latest Session")

        return CodexLocalAnalyticsReport(
            today: today,
            thisMonth: thisMonth,
            latestSession: latestSession,
            capturedAt: now()
        )
    }

    private func readCache() -> CachedReport? {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path),
              let data = try? Data(contentsOf: cacheFileURL) else {
            return nil
        }

        return try? JSONDecoder().decode(CachedReport.self, from: data)
    }

    private func writeCache(_ cache: CachedReport) throws {
        let directory = cacheFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(cache)
        try data.write(to: cacheFileURL, options: .atomic)
    }

    private func newestSessionModifiedAt() -> Date? {
        let sessionsDirectory = codexDirectory.appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var newestDate: Date?
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modifiedAt = values.contentModificationDate else {
                continue
            }

            if newestDate == nil || modifiedAt > newestDate! {
                newestDate = modifiedAt
            }
        }

        return newestDate
    }

    private func isStale(
        cache: CachedReport,
        newestSessionModifiedAt: Date?,
        timezoneIdentifier: String,
        preferredRunner: String?
    ) -> Bool {
        if cache.timezoneIdentifier != timezoneIdentifier {
            return true
        }
        if let preferredRunner, cache.runner != preferredRunner {
            return true
        }
        if cache.newestSessionModifiedAt != newestSessionModifiedAt {
            return true
        }
        return now().timeIntervalSince(cache.generatedAt) > cacheTTL
    }
}

// MARK: - Runner

private extension CodexLocalAnalyticsAnalyzer {
    enum Runner: String {
        case bunx
        case npx

        func arguments(for command: String, timezoneIdentifier: String) -> [String] {
            [
                "-y",
                "@ccusage/codex@latest",
                command,
                "--json",
                "--offline",
                "--timezone",
                timezoneIdentifier,
            ]
        }
    }

    struct CachedReport: Codable {
        let generatedAt: Date
        let newestSessionModifiedAt: Date?
        let timezoneIdentifier: String
        let runner: String
        let report: CodexLocalAnalyticsReport
    }

    struct DailyPayload: Decodable {
        let daily: [DailyEntry]
    }

    struct DailyEntry: Decodable {
        let date: String
        let cachedInputTokens: Int
        let totalTokens: Int
        let reasoningOutputTokens: Int
        let costUSD: Double
    }

    struct MonthlyPayload: Decodable {
        let monthly: [MonthlyEntry]
    }

    struct MonthlyEntry: Decodable {
        let month: String
        let cachedInputTokens: Int
        let totalTokens: Int
        let reasoningOutputTokens: Int
        let costUSD: Double
    }

    struct SessionPayload: Decodable {
        let sessions: [SessionEntry]
    }

    struct SessionEntry: Decodable {
        let lastActivity: String
        let cachedInputTokens: Int
        let totalTokens: Int
        let reasoningOutputTokens: Int
        let costUSD: Double
    }
}
