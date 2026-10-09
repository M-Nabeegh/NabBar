import Foundation
import Observation

/// What a coding agent is doing right now, as the menu bar shows it: a blue dot
/// while it works on a turn, a green one once it finished, nothing otherwise.
public enum AgentActivity: Equatable, Sendable {
    case idle
    case working
    case finished(at: Date)

    /// A working session that has written nothing for this long has stopped
    /// without saying so (closed terminal, crash).
    static let staleAfter: TimeInterval = 30 * 60
    /// How long an unseen finish keeps its dot.
    static let finishedShownFor: TimeInterval = 2 * 60 * 60

    /// One answer for a tool from all its recent sessions, each with the time
    /// its log last changed: working if any session works, else the latest
    /// finish not yet seen.
    public static func combined(
        _ sessions: [(activity: AgentActivity, modifiedAt: Date)],
        now: Date,
        acknowledgedAt: Date?
    ) -> AgentActivity {
        if sessions.contains(where: { $0.activity == .working && now.timeIntervalSince($0.modifiedAt) < staleAfter }) {
            return .working
        }
        let latest = sessions.compactMap { session -> Date? in
            if case .finished(let at) = session.activity { return at }
            return nil
        }.max()
        guard let latest,
              now.timeIntervalSince(latest) < finishedShownFor,
              latest > (acknowledgedAt ?? .distantPast) else { return .idle }
        return .finished(at: latest)
    }
}

/// Reads the end of a session log. Read only; nothing here writes to a log.
public enum AgentLog {
    /// Claude Code's transcript (`~/.claude/projects/<project>/<session>.jsonl`):
    /// a turn ends with an assistant message whose `stop_reason` is `end_turn`;
    /// a prompt or a tool result means it is still going.
    public static func claude(_ tail: String) -> AgentActivity {
        var activity = AgentActivity.idle
        for object in objects(in: tail) {
            guard let message = object["message"] as? [String: Any] else { continue }
            switch object["type"] as? String {
            case "assistant":
                if ["end_turn", "stop_sequence"].contains(message["stop_reason"] as? String ?? "") {
                    activity = date(object["timestamp"]).map { .finished(at: $0) } ?? .idle
                } else {
                    activity = .working
                }
            case "user":
                if object["isMeta"] as? Bool == true { continue }
                let text = Self.text(of: message["content"])
                if text.hasPrefix("<command-") || text.hasPrefix("<local-command") { continue }
                activity = text.contains("[Request interrupted by user") ? .idle : .working
            default:
                continue
            }
        }
        return activity
    }

    /// Codex's rollout (`~/.codex/sessions/YYYY/MM/DD/rollout-….jsonl`): a turn
    /// runs from `task_started` to `task_complete`, or to `turn_aborted`.
    public static func codex(_ tail: String) -> AgentActivity {
        var activity = AgentActivity.idle
        for object in objects(in: tail) where object["type"] as? String == "event_msg" {
            switch (object["payload"] as? [String: Any])?["type"] as? String {
            case "task_started": activity = .working
            case "task_complete": activity = date(object["timestamp"]).map { .finished(at: $0) } ?? .idle
            case "turn_aborted": activity = .idle
            default: continue
            }
        }
        return activity
    }

    // MARK: - JSON lines

    private static func objects(in tail: String) -> [[String: Any]] {
        tail.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.first == "{" else { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
    }

    private static func text(of content: Any?) -> String {
        if let text = content as? String { return text }
        let parts = (content as? [[String: Any]]) ?? []
        return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Watches Claude Code's and Codex's session logs and keeps one activity per
/// tool, keyed by provider id. Polls every two seconds; only logs changed in
/// the last two hours are read, and only their last 256 KB.
@MainActor
@Observable
public final class AgentActivityMonitor {
    public private(set) var activities: [String: AgentActivity] = [:]

    private var acknowledgedAt: [String: Date] = [:]
    private var task: Task<Void, Never>?
    private let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// The menu was opened: a finish shown so far has been seen.
    public func acknowledge() {
        let now = Date()
        for id in activities.keys { acknowledgedAt[id] = now }
        activities = activities.mapValues { activity in
            if case .finished = activity { return .idle }
            return activity
        }
    }

    private func poll() async {
        let home = self.home
        let sessions = await Task.detached(priority: .utility) {
            (claude: Self.read(Self.claudeLogs(home: home), with: AgentLog.claude),
             codex: Self.read(Self.codexLogs(home: home), with: AgentLog.codex))
        }.value
        let now = Date()
        let next = [
            "claude": AgentActivity.combined(sessions.claude, now: now, acknowledgedAt: acknowledgedAt["claude"]),
            "codex": AgentActivity.combined(sessions.codex, now: now, acknowledgedAt: acknowledgedAt["codex"]),
        ]
        if next != activities { activities = next }
    }

    // MARK: - Files

    nonisolated private static let window: TimeInterval = 2 * 60 * 60
    nonisolated private static let tailBytes = 256 * 1024

    nonisolated private static func claudeLogs(home: URL) -> [URL] {
        let projects = home.appendingPathComponent(".claude/projects", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return folders.flatMap { jsonl(in: $0) }
    }

    nonisolated private static func codexLogs(home: URL) -> [URL] {
        let sessions = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let calendar = Calendar.current
        return [0, -1].flatMap { offset -> [URL] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { return [] }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let folder = sessions.appendingPathComponent(String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
            return jsonl(in: folder)
        }
    }

    nonisolated private static func jsonl(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "jsonl" }
    }

    nonisolated private static func read(
        _ files: [URL],
        with parse: (String) -> AgentActivity
    ) -> [(activity: AgentActivity, modifiedAt: Date)] {
        let cutoff = Date().addingTimeInterval(-window)
        return files.compactMap { file in
            guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  modified > cutoff,
                  let tail = tail(of: file) else { return nil }
            return (parse(tail), modified)
        }
    }

    nonisolated private static func tail(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
