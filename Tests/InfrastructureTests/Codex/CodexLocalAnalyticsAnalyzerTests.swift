import Foundation
import Testing
@testable import Infrastructure
@testable import Domain

@Suite("CodexLocalAnalyticsAnalyzer Tests")
struct CodexLocalAnalyticsAnalyzerTests {
    @Test
    func `refresh prefers bunx when available`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createSessionFile(in: tempDir, name: "one.jsonl")

        let executor = StubCLIExecutor(
            locatedBinaries: ["bunx": "/opt/homebrew/bin/bunx", "npx": "/opt/homebrew/bin/npx"],
            responses: [
                .init(binary: "bunx", command: "daily"): .success(.init(output: sampleDailyJSON(cost: 10))),
                .init(binary: "bunx", command: "monthly"): .success(.init(output: sampleMonthlyJSON(cost: 40))),
                .init(binary: "bunx", command: "session"): .success(.init(output: sampleSessionJSON(cost: 5))),
            ]
        )

        let analyzer = makeAnalyzer(codexDir: tempDir, cacheFile: tempDir.appendingPathComponent("cache.json"), executor: executor)
        let report = try await analyzer.refresh(policy: .force)

        #expect(report?.today.formattedCost == "$10.00")
        #expect(executor.calls.map(\.binary) == ["bunx", "bunx", "bunx"])
    }

    @Test
    func `refresh falls back to npx when bunx execution fails`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createSessionFile(in: tempDir, name: "one.jsonl")

        let executor = StubCLIExecutor(
            locatedBinaries: ["bunx": "/opt/homebrew/bin/bunx", "npx": "/opt/homebrew/bin/npx"],
            responses: [
                .init(binary: "bunx", command: "daily"): .failure(ProbeError.executionFailed("bunx failed")),
                .init(binary: "npx", command: "daily"): .success(.init(output: sampleDailyJSON(cost: 11))),
                .init(binary: "npx", command: "monthly"): .success(.init(output: sampleMonthlyJSON(cost: 44))),
                .init(binary: "npx", command: "session"): .success(.init(output: sampleSessionJSON(cost: 6))),
            ]
        )

        let analyzer = makeAnalyzer(codexDir: tempDir, cacheFile: tempDir.appendingPathComponent("cache.json"), executor: executor)
        let report = try await analyzer.refresh(policy: .force)

        #expect(report?.today.formattedCost == "$11.00")
        #expect(executor.calls.map(\.binary) == ["bunx", "npx", "npx", "npx"])
    }

    @Test
    func `refresh reuses cache when sessions have not changed`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createSessionFile(in: tempDir, name: "one.jsonl")
        let cacheFile = tempDir.appendingPathComponent("cache.json")

        let executor = StubCLIExecutor(
            locatedBinaries: ["bunx": "/opt/homebrew/bin/bunx"],
            responses: [
                .init(binary: "bunx", command: "daily"): .success(.init(output: sampleDailyJSON(cost: 12))),
                .init(binary: "bunx", command: "monthly"): .success(.init(output: sampleMonthlyJSON(cost: 48))),
                .init(binary: "bunx", command: "session"): .success(.init(output: sampleSessionJSON(cost: 7))),
            ]
        )

        let analyzer = makeAnalyzer(codexDir: tempDir, cacheFile: cacheFile, executor: executor)
        let first = try await analyzer.refresh(policy: .force)
        let second = try await analyzer.refresh(policy: .ifNeeded)

        #expect(first == second)
        #expect(executor.calls.count == 3)
        let cached = await analyzer.cachedReport()
        #expect(cached == first)
    }

    @Test
    func `refresh invalidates cache when newest session mtime changes`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sessionFile = try createSessionFile(in: tempDir, name: "one.jsonl")
        let cacheFile = tempDir.appendingPathComponent("cache.json")

        let executor = StubCLIExecutor(
            locatedBinaries: ["bunx": "/opt/homebrew/bin/bunx"],
            responses: [
                .init(binary: "bunx", command: "daily"): .success(.init(output: sampleDailyJSON(cost: 12))),
                .init(binary: "bunx", command: "monthly"): .success(.init(output: sampleMonthlyJSON(cost: 48))),
                .init(binary: "bunx", command: "session"): .success(.init(output: sampleSessionJSON(cost: 7))),
            ]
        )

        let analyzer = makeAnalyzer(codexDir: tempDir, cacheFile: cacheFile, executor: executor)
        _ = try await analyzer.refresh(policy: .force)

        let newDate = Date().addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: sessionFile.path)

        executor.responses[.init(binary: "bunx", command: "daily")] = .success(.init(output: sampleDailyJSON(cost: 20)))
        executor.responses[.init(binary: "bunx", command: "monthly")] = .success(.init(output: sampleMonthlyJSON(cost: 80)))
        executor.responses[.init(binary: "bunx", command: "session")] = .success(.init(output: sampleSessionJSON(cost: 9)))

        let refreshed = try await analyzer.refresh(policy: .ifNeeded)

        #expect(refreshed?.today.formattedCost == "$20.00")
        #expect(executor.calls.count == 6)
    }
}

// MARK: - Test Helpers

private extension CodexLocalAnalyticsAnalyzerTests {
    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-local-analytics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func createSessionFile(in directory: URL, name: String) throws -> URL {
        let sessionsDirectory = directory
            .appendingPathComponent("sessions/2026/04/18", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        let file = sessionsDirectory.appendingPathComponent(name)
        try "{}\n".data(using: .utf8)?.write(to: file)
        return file
    }

    func makeAnalyzer(codexDir: URL, cacheFile: URL, executor: StubCLIExecutor) -> CodexLocalAnalyticsAnalyzer {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem") ?? .current
        return CodexLocalAnalyticsAnalyzer(
            cliExecutor: executor,
            codexDirectory: codexDir,
            cacheFileURL: cacheFile,
            calendar: calendar,
            now: { Date(timeIntervalSince1970: 1_776_500_000) }
        )
    }

    func sampleDailyJSON(cost: Double) -> String {
        """
        {
          "daily": [
            {
              "date": "Apr 18, 2026",
              "cachedInputTokens": 120791424,
              "totalTokens": 125389222,
              "reasoningOutputTokens": 238763,
              "costUSD": \(cost)
            }
          ],
          "totals": {}
        }
        """
    }

    func sampleMonthlyJSON(cost: Double) -> String {
        """
        {
          "monthly": [
            {
              "month": "Apr 2026",
              "cachedInputTokens": 1673207552,
              "totalTokens": 1771088650,
              "reasoningOutputTokens": 2795099,
              "costUSD": \(cost)
            }
          ],
          "totals": {}
        }
        """
    }

    func sampleSessionJSON(cost: Double) -> String {
        """
        {
          "sessions": [
            {
              "lastActivity": "2026-04-18T10:14:40.936Z",
              "cachedInputTokens": 54255872,
              "totalTokens": 56096805,
              "reasoningOutputTokens": 111538,
              "costUSD": \(cost)
            }
          ],
          "totals": {}
        }
        """
    }
}

private final class StubCLIExecutor: CLIExecutor, @unchecked Sendable {
    struct CommandKey: Hashable {
        let binary: String
        let command: String
    }

    struct Call: Equatable {
        let binary: String
        let command: String
    }

    let locatedBinaries: [String: String]
    var responses: [CommandKey: Result<CLIResult, Error>]
    private(set) var calls: [Call] = []

    init(locatedBinaries: [String: String], responses: [CommandKey: Result<CLIResult, Error>]) {
        self.locatedBinaries = locatedBinaries
        self.responses = responses
    }

    func locate(_ binary: String) -> String? {
        locatedBinaries[binary]
    }

    func execute(
        binary: String,
        args: [String],
        input _: String?,
        timeout _: TimeInterval,
        workingDirectory _: URL?,
        autoResponses _: [String: String]
    ) throws -> CLIResult {
        guard let command = args.first(where: { ["daily", "monthly", "session"].contains($0) }) else {
            throw ProbeError.executionFailed("Missing command")
        }

        calls.append(.init(binary: binary, command: command))
        guard let result = responses[.init(binary: binary, command: command)] else {
            throw ProbeError.executionFailed("No stubbed response for \(binary) \(command)")
        }
        return try result.get()
    }
}
