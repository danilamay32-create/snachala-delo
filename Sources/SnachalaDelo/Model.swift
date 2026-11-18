import Foundation
import Shared
import Combine

/// Связь окна с фоновой службой. Состояние всегда берётся у службы, своё не хранится.
final class Model: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var online = false
    @Published var error: String?
    /// Тикает раз в секунду, чтобы обновлялись отсчёты.
    @Published private(set) var now = Date()

    private var timer: Timer?
    private let io = DispatchQueue(label: "ru.snachaladelo.client")
    private var inFlight = false

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
            self?.refresh()
        }
    }

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        send(Request(.state)) { [weak self] in self?.inFlight = false }
    }

    func send(_ req: Request, done: (() -> Void)? = nil) {
        io.async {
            let result = Result { try IPC.send(req) }
            DispatchQueue.main.async {
                switch result {
                case .success(let resp):
                    self.online = true
                    if let s = resp.snapshot, s != self.snapshot { self.snapshot = s }
                    if req.cmd != .state { self.error = resp.error }
                case .failure:
                    self.online = false
                    if req.cmd != .state { self.error = "Фоновая служба не отвечает. Переустанови приложение." }
                }
                done?()
            }
        }
    }

    // MARK: Actions

    func add(_ title: String, _ date: Date) { send(Request(.add, title: title, date: date)) }
    func complete(_ t: TaskItem) { send(Request(.complete, id: t.id)) }
    func requestDelete(_ t: TaskItem) { send(Request(.requestDelete, id: t.id)) }
    func cancelDelete(_ t: TaskItem) { send(Request(.cancelDelete, id: t.id)) }
    func reschedule(_ t: TaskItem, to d: Date) { send(Request(.reschedule, id: t.id, date: d)) }
    func startPass() { send(Request(.startPass)) }
    func addSite(_ s: String) { send(Request(.addSite, site: s)) }
    func removeSite(_ s: String) { send(Request(.removeSite, site: s)) }
    func addApp(_ a: BlockedApp) { send(Request(.addApp, app: a)) }
    func removeApp(_ a: BlockedApp) { send(Request(.removeApp, app: a)) }

    // MARK: Status

    enum Status { case offline, free, locked, pass }

    var status: Status {
        guard online, let s = snapshot else { return .offline }
        if s.locked { return .locked }
        if s.hasLockingTasks { return .pass }
        return .free
    }
}
