import Foundation
import Testing
@testable import Domain

/// What Claude Code or Codex is doing, read from the end of its session log:
/// working on a turn, finished one, or nothing to show.
@Suite
struct AgentActivityTests {
    private let t0 = ISO8601DateFormatter().date(from: "2026-10-09T13:32:04Z")!

    private func lines(_ objects: [String]) -> String { objects.joined(separator: "\n") }

    // MARK: - Claude Code transcripts

    @Test
    func `a Claude turn that ended is finished at its time`() {
        let log = lines([
            #"{"type":"user","message":{"role":"user","content":"fix the build"},"timestamp":"2026-10-09T13:30:00.000Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use"}]},"timestamp":"2026-10-09T13:31:00.000Z"}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result"}]},"timestamp":"2026-10-09T13:31:30.000Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text"}]},"timestamp":"2026-10-09T13:32:04.000Z"}"#,
            #"{"type":"system","subtype":"stop_hook_summary","timestamp":"2026-10-09T13:32:07.000Z"}"#,
        ])

        #expect(AgentLog.claude(log) == .finished(at: t0))
    }

    @Test
    func `a Claude turn waiting on a tool is working`() {
        let log = lines([
            #"{"type":"user","message":{"role":"user","content":"fix the build"},"timestamp":"2026-10-09T13:30:00.000Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use"}]},"timestamp":"2026-10-09T13:31:00.000Z"}"#,
            #"{"type":"last-prompt","timestamp":"2026-10-09T13:31:01.000Z"}"#,
        ])

        #expect(AgentLog.claude(log) == .working)
    }

    @Test
    func `a prompt Claude has not answered yet is working`() {
        let log = #"{"type":"user","message":{"role":"user","content":"and the tests"},"timestamp":"2026-10-09T13:40:00.000Z"}"#

        #expect(AgentLog.claude(log) == .working)
    }

    @Test
    func `an interrupted Claude turn is idle`() {
        let log = lines([
            #"{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use"}]},"timestamp":"2026-10-09T13:31:00.000Z"}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]},"timestamp":"2026-10-09T13:31:05.000Z"}"#,
        ])

        #expect(AgentLog.claude(log) == .idle)
    }

    @Test
    func `a local slash command is not work`() {
        let log = lines([
            #"{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text"}]},"timestamp":"2026-10-09T13:32:04.000Z"}"#,
            #"{"type":"user","isMeta":true,"message":{"role":"user","content":"<local-command-caveat>…</local-command-caveat>"},"timestamp":"2026-10-09T13:33:00.000Z"}"#,
            #"{"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>"},"timestamp":"2026-10-09T13:33:00.000Z"}"#,
        ])

        #expect(AgentLog.claude(log) == .finished(at: t0))
    }

    @Test
    func `a cut first line and junk are skipped`() {
        let log = "ated\":true}\n" + #"{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[]},"timestamp":"2026-10-09T13:32:04Z"}"# + "\nnot json"

        #expect(AgentLog.claude(log) == .finished(at: t0))
    }

    // MARK: - Codex rollouts

    @Test
    func `a Codex task that completed is finished at its time`() {
        let log = lines([
            #"{"timestamp":"2026-10-09T13:30:00.000Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-10-09T13:31:00.000Z","type":"response_item","payload":{"type":"function_call"}}"#,
            #"{"timestamp":"2026-10-09T13:32:04.000Z","type":"event_msg","payload":{"type":"task_complete"}}"#,
            #"{"timestamp":"2026-10-09T13:32:05.000Z","type":"event_msg","payload":{"type":"token_count"}}"#,
        ])

        #expect(AgentLog.codex(log) == .finished(at: t0))
    }

    @Test
    func `a started Codex task is working`() {
        let log = lines([
            #"{"timestamp":"2026-10-09T13:20:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}"#,
            #"{"timestamp":"2026-10-09T13:30:00.000Z","type":"event_msg","payload":{"type":"task_started"}}"#,
        ])

        #expect(AgentLog.codex(log) == .working)
    }

    @Test
    func `an aborted Codex turn is idle`() {
        let log = lines([
            #"{"timestamp":"2026-10-09T13:30:00.000Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-10-09T13:30:20.000Z","type":"event_msg","payload":{"type":"turn_aborted"}}"#,
        ])

        #expect(AgentLog.codex(log) == .idle)
    }

    // MARK: - One answer per tool

    @Test
    func `any session still working makes the tool working`() {
        let now = t0.addingTimeInterval(60)
        let sessions: [(AgentActivity, Date)] = [(.finished(at: t0), t0), (.working, now.addingTimeInterval(-5))]

        #expect(AgentActivity.combined(sessions, now: now, acknowledgedAt: nil) == .working)
    }

    @Test
    func `a session silent for half an hour is no longer working`() {
        let now = t0.addingTimeInterval(31 * 60)

        #expect(AgentActivity.combined([(.working, t0)], now: now, acknowledgedAt: nil) == .idle)
    }

    @Test
    func `the latest finish shows until it is seen`() {
        let earlier = t0.addingTimeInterval(-600)
        let sessions: [(AgentActivity, Date)] = [(.finished(at: earlier), earlier), (.finished(at: t0), t0)]

        #expect(AgentActivity.combined(sessions, now: t0.addingTimeInterval(60), acknowledgedAt: nil) == .finished(at: t0))
        #expect(AgentActivity.combined(sessions, now: t0.addingTimeInterval(60), acknowledgedAt: t0.addingTimeInterval(30)) == .idle)
    }

    @Test
    func `a finish older than two hours is dropped`() {
        #expect(AgentActivity.combined([(.finished(at: t0), t0)], now: t0.addingTimeInterval(121 * 60), acknowledgedAt: nil) == .idle)
    }

    // MARK: - Finding Codex's logs

    @Test
    @MainActor
    func `a resumed Codex conversation is found in the folder of the day it started`() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let old = home.appendingPathComponent(".codex/sessions/2026/09/23", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let rollout = old.appendingPathComponent("rollout-2026-09-23T21-13-17.jsonl")
        try Data("{}".utf8).write(to: rollout)

        let found = AgentActivityMonitor.codexLogs(home: home)

        #expect(found.map(\.lastPathComponent) == ["rollout-2026-09-23T21-13-17.jsonl"])
    }

    @Test
    func `an unchanged log is not read again`() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("rollout.jsonl")
        try Data(#"{"timestamp":"2026-10-09T13:30:00Z","type":"event_msg","payload":{"type":"task_started"}}"#.utf8).write(to: log)
        let cache = ParsedLogs()

        let first = AgentActivityMonitor.read([log], with: AgentLog.codex, cache: cache)
        let second = AgentActivityMonitor.read([log], with: AgentLog.codex, cache: cache)

        #expect(first.map(\.activity) == [.working])
        #expect(second.map(\.activity) == [.working])
        #expect(cache.reads == 1)
    }
}
