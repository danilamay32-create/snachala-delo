import Foundation

public enum Paths {
    public static let socket = "/var/run/ru.snachaladelo.sock"
    public static let stateDir = "/Library/Application Support/SnachalaDelo"
    public static let stateFile = stateDir + "/state.json"
    public static let hosts = "/private/etc/hosts"
}

public enum Rules {
    /// Задача начинает блокировать, когда до дедлайна меньше суток.
    public static let lockWindow: TimeInterval = 24 * 3600
    public static let passDuration: TimeInterval = 15 * 60
    public static let deleteDelay: TimeInterval = 30
    /// После первого переноса дедлайн можно двигать не дальше чем на сутки от текущего момента.
    public static let laterRescheduleLimit: TimeInterval = 24 * 3600
    /// Закрытые задачи висят в списке ещё столько, потом убираются.
    public static let keepDone: TimeInterval = 2 * 24 * 3600
}

public struct TaskItem: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var deadline: Date
    public var createdAt: Date
    public var doneAt: Date?
    public var rescheduleCount: Int
    public var deleteAt: Date?

    public init(title: String, deadline: Date, now: Date = Date()) {
        id = UUID()
        self.title = title
        self.deadline = deadline
        createdAt = now
        doneAt = nil
        rescheduleCount = 0
        deleteAt = nil
    }

    public var isDone: Bool { doneAt != nil }

    public func isLocking(at now: Date) -> Bool {
        !isDone && deadline.timeIntervalSince(now) < Rules.lockWindow
    }

    public func isOverdue(at now: Date) -> Bool {
        !isDone && deadline < now
    }
}

public struct BlockedApp: Codable, Equatable, Hashable, Identifiable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }
    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct Snapshot: Codable, Equatable {
    public var now: Date
    public var tasks: [TaskItem]
    /// Есть незакрытые задачи с дедлайном меньше суток (без учёта передышки).
    public var hasLockingTasks: Bool
    /// Реально блокирует прямо сейчас (с учётом передышки).
    public var locked: Bool
    public var passUntil: Date?
    public var passAvailableToday: Bool
    public var sites: [String]
    public var apps: [BlockedApp]

    public init(now: Date, tasks: [TaskItem], hasLockingTasks: Bool, locked: Bool, passUntil: Date?,
                passAvailableToday: Bool, sites: [String], apps: [BlockedApp]) {
        self.now = now
        self.tasks = tasks
        self.hasLockingTasks = hasLockingTasks
        self.locked = locked
        self.passUntil = passUntil
        self.passAvailableToday = passAvailableToday
        self.sites = sites
        self.apps = apps
    }

    public var lockingTasks: [TaskItem] {
        tasks.filter { $0.isLocking(at: now) }.sorted { $0.deadline < $1.deadline }
    }
}

public enum Command: String, Codable {
    case state, add, complete, requestDelete, cancelDelete, reschedule, startPass
    case addSite, removeSite, addApp, removeApp
}

public struct Request: Codable {
    public var cmd: Command
    public var id: UUID?
    public var title: String?
    public var date: Date?
    public var site: String?
    public var app: BlockedApp?

    public init(_ cmd: Command, id: UUID? = nil, title: String? = nil, date: Date? = nil,
                site: String? = nil, app: BlockedApp? = nil) {
        self.cmd = cmd
        self.id = id
        self.title = title
        self.date = date
        self.site = site
        self.app = app
    }
}

public struct Response: Codable {
    public var error: String?
    public var snapshot: Snapshot?
    public init(error: String? = nil, snapshot: Snapshot? = nil) {
        self.error = error
        self.snapshot = snapshot
    }
}

public enum Defaults {
    public static let sites: [String] = [
        "youtube.com", "youtu.be", "googlevideo.com",
        "netflix.com", "nflxvideo.net",
        "kinopoisk.ru", "hd.kinopoisk.ru",
        "ivi.ru", "okko.tv", "wink.ru", "kion.ru", "start.ru",
        "rutube.ru", "vkvideo.ru", "twitch.tv", "tiktok.com",
        "hdrezka.ag", "rezka.ag", "hdrezka.me", "hdrezka.co", "hdrezka.website",
        "animego.org", "animego.one", "animego.me",
    ]

    public static let apps: [BlockedApp] = [
        BlockedApp(bundleID: "com.apple.TV", name: "Apple TV"),
        BlockedApp(bundleID: "com.colliderli.iina", name: "IINA"),
        BlockedApp(bundleID: "org.videolan.vlc", name: "VLC"),
        BlockedApp(bundleID: "com.firecore.infuse", name: "Infuse"),
        BlockedApp(bundleID: "com.valvesoftware.steam", name: "Steam"),
    ]

    /// Чистит ввод: «https://www.YouTube.com/watch?v=1» → «youtube.com».
    public static func normalizeSite(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let i = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" || $0 == ":" }) { s = String(s[..<i]) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard s.contains("."), !s.hasPrefix("."), !s.hasSuffix("."),
              s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return s
    }
}
