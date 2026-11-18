import Foundation
import Shared

struct State: Codable {
    var tasks: [TaskItem] = []
    var sites: [String] = Defaults.sites
    var apps: [BlockedApp] = Defaults.apps
    var passUntil: Date?
    var lastPassDay: String?
    /// Какой версии список сайтов по умолчанию уже добавлен (nil — самая первая).
    var sitesVersion: Int?
    /// DNS-настройки сетевых служб до включения фильтра: имя службы → серверы ([] — автоматически).
    var dnsBackup: [String: [String]]?
}

/// Хранит задачи и проверяет все правила. Все вызовы идут с одной последовательной очереди.
final class Store {
    private(set) var state = State()
    private let fm = FileManager.default

    init() {
        load()
    }

    // MARK: Persistence

    private func load() {
        if let data = fm.contents(atPath: Paths.stateFile),
           let s = try? IPC.decoder.decode(State.self, from: data) {
            state = s
        }
        migrateDefaults()
    }

    /// Добавляет новые записи списка по умолчанию, ничего не удаляя из настроек.
    func migrateDefaults() {
        guard (state.sitesVersion ?? 1) < Defaults.sitesVersion else { return }
        for s in Defaults.sites where !state.sites.contains(s) { state.sites.append(s) }
        state.sitesVersion = Defaults.sitesVersion
        save()
    }

    func setDNSBackup(_ b: [String: [String]]?) {
        state.dnsBackup = b
        save()
    }

    func save() {
        do {
            try fm.createDirectory(atPath: Paths.stateDir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o755])
            let data = try IPC.encoder.encode(state)
            try data.write(to: URL(fileURLWithPath: Paths.stateFile), options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: Paths.stateFile)
        } catch {
            log("save failed: \(error)")
        }
    }

    // MARK: Derived

    static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func hasLockingTasks(_ now: Date) -> Bool {
        state.tasks.contains { $0.isLocking(at: now) }
    }

    func passActive(_ now: Date) -> Bool {
        if let p = state.passUntil, p > now { return true }
        return false
    }

    func isLocked(_ now: Date) -> Bool {
        hasLockingTasks(now) && !passActive(now)
    }

    func snapshot(_ now: Date = Date()) -> Snapshot {
        Snapshot(
            now: now,
            tasks: state.tasks.sorted { a, b in
                if a.isDone != b.isDone { return !a.isDone }
                return a.deadline < b.deadline
            },
            hasLockingTasks: hasLockingTasks(now),
            locked: isLocked(now),
            passUntil: passActive(now) ? state.passUntil : nil,
            passAvailableToday: state.lastPassDay != Store.dayKey(now),
            sites: state.sites,
            apps: state.apps
        )
    }

    // MARK: Housekeeping

    /// Возвращает true, если что-то поменялось.
    func tick(_ now: Date) -> Bool {
        let before = state.tasks.count
        state.tasks.removeAll { t in
            if let d = t.deleteAt, d <= now { return true }
            if let done = t.doneAt, now.timeIntervalSince(done) > Rules.keepDone { return true }
            return false
        }
        var changed = state.tasks.count != before
        if let p = state.passUntil, p <= now {
            state.passUntil = nil
            changed = true
        }
        return changed
    }

    // MARK: Commands

    struct RuleError: Error { let message: String }

    private func index(_ id: UUID?) throws -> Int {
        guard let id = id, let i = state.tasks.firstIndex(where: { $0.id == id }) else {
            throw RuleError(message: "Задача не найдена")
        }
        return i
    }

    func handle(_ req: Request, now: Date = Date()) -> Response {
        do {
            try apply(req, now: now)
            if req.cmd != .state { save() }
            return Response(snapshot: snapshot(now))
        } catch let e as RuleError {
            return Response(error: e.message, snapshot: snapshot(now))
        } catch {
            return Response(error: "\(error)", snapshot: snapshot(now))
        }
    }

    private func apply(_ req: Request, now: Date) throws {
        switch req.cmd {
        case .state:
            break

        case .add:
            let title = (req.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw RuleError(message: "Напиши, что нужно сделать") }
            guard let date = req.date else { throw RuleError(message: "Выбери дедлайн") }
            guard date > now else { throw RuleError(message: "Дедлайн уже прошёл") }
            state.tasks.append(TaskItem(title: String(title.prefix(200)), deadline: date, now: now))

        case .complete:
            let i = try index(req.id)
            if state.tasks[i].doneAt == nil {
                state.tasks[i].doneAt = now
                state.tasks[i].deleteAt = nil
            }

        case .requestDelete:
            let i = try index(req.id)
            if state.tasks[i].isDone {
                // Закрытая задача ничего не блокирует, её можно убрать сразу.
                state.tasks.remove(at: i)
            } else if state.tasks[i].deleteAt == nil {
                state.tasks[i].deleteAt = now.addingTimeInterval(Rules.deleteDelay)
            }

        case .cancelDelete:
            let i = try index(req.id)
            state.tasks[i].deleteAt = nil

        case .reschedule:
            let i = try index(req.id)
            guard !state.tasks[i].isDone else { throw RuleError(message: "Задача уже закрыта") }
            guard let date = req.date, date > now else { throw RuleError(message: "Новый дедлайн должен быть в будущем") }
            let old = state.tasks[i].deadline
            if date <= old {
                // Сдвинуть раньше можно всегда, это не считается переносом.
                state.tasks[i].deadline = date
                break
            }
            if state.tasks[i].rescheduleCount >= 1 && date > now.addingTimeInterval(Rules.laterRescheduleLimit) {
                throw RuleError(message: "Эту задачу уже переносили. Теперь дальше чем на сутки не отодвинуть.")
            }
            state.tasks[i].deadline = date
            state.tasks[i].rescheduleCount += 1

        case .startPass:
            guard hasLockingTasks(now) else { throw RuleError(message: "Сейчас и так ничего не блокируется") }
            guard !passActive(now) else { break }
            let today = Store.dayKey(now)
            guard state.lastPassDay != today else {
                throw RuleError(message: "Передышка сегодня уже была. Следующая завтра.")
            }
            state.lastPassDay = today
            state.passUntil = now.addingTimeInterval(Rules.passDuration)

        case .addSite:
            guard let s = req.site.flatMap(Defaults.normalizeSite) else {
                throw RuleError(message: "Не похоже на адрес сайта")
            }
            if !state.sites.contains(s) { state.sites.append(s) }

        case .removeSite:
            guard !hasLockingTasks(now) else {
                throw RuleError(message: "Пока есть срочные задачи, список можно только пополнять")
            }
            state.sites.removeAll { $0 == req.site }

        case .addApp:
            guard let app = req.app, !app.bundleID.isEmpty else { throw RuleError(message: "Не удалось прочитать приложение") }
            if app.bundleID == "ru.snachaladelo.app" { throw RuleError(message: "Себя блокировать не будем 🙂") }
            if !state.apps.contains(where: { $0.bundleID == app.bundleID }) { state.apps.append(app) }

        case .removeApp:
            guard !hasLockingTasks(now) else {
                throw RuleError(message: "Пока есть срочные задачи, список можно только пополнять")
            }
            state.apps.removeAll { $0.bundleID == req.app?.bundleID }
        }
    }
}

func log(_ s: String) {
    FileHandle.standardError.write(("[snachaladelo] " + s + "\n").data(using: .utf8)!)
}
