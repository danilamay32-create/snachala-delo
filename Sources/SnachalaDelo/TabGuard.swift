import AppKit
import Shared

/// Пока идёт блокировка, раз в 2 секунды смотрит адреса открытых вкладок в браузерах
/// и переключает запрещённые на страницу «Сначала дело». Работает при любом VPN и DNS:
/// проверяется адрес, который показывает сам браузер.
final class TabGuard {
    struct Browser {
        let bundleID: String
        let name: String
    }

    /// Браузеры с AppleScript-доступом к вкладкам (Safari и семейство Chrome).
    static let browsers: [Browser] = [
        Browser(bundleID: "com.apple.Safari", name: "Safari"),
        Browser(bundleID: "com.apple.SafariTechnologyPreview", name: "Safari"),
        Browser(bundleID: "com.google.Chrome", name: "Chrome"),
        Browser(bundleID: "ru.yandex.desktop.yandex-browser", name: "Яндекс Браузер"),
        Browser(bundleID: "com.microsoft.edgemac", name: "Edge"),
        Browser(bundleID: "com.brave.Browser", name: "Brave"),
        Browser(bundleID: "company.thebrowser.Browser", name: "Arc"),
        Browser(bundleID: "com.operasoftware.Opera", name: "Opera"),
        Browser(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi"),
        Browser(bundleID: "org.chromium.Chromium", name: "Chromium"),
    ]

    private let queue = DispatchQueue(label: "ru.snachaladelo.tabguard")
    private var busy = false
    /// Вызывается на главном потоке, если macOS не дала доступ к браузеру.
    var onDenied: ((String) -> Void)?
    private var deniedReported = Set<String>()

    /// snapshot берётся на главном потоке и передаётся сюда.
    func check(_ s: Snapshot) {
        guard s.locked, !busy else { return }
        let running = TabGuard.browsers.filter {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty
        }
        guard !running.isEmpty else { return }
        busy = true
        let page = blockPageURL(s)
        queue.async { [weak self] in
            guard let self = self else { return }
            for b in running { self.scan(b, sites: s.sites, page: page) }
            DispatchQueue.main.async { self.busy = false }
        }
    }

    // MARK: AppleScript

    private func scan(_ b: Browser, sites: [String], page: (String) -> String) {
        let list = """
        set out to ""
        tell application id "\(b.bundleID)"
          set wi to 0
          repeat with w in windows
            set wi to wi + 1
            try
              set ti to 0
              repeat with t in tabs of w
                set ti to ti + 1
                set out to out & wi & (character id 9) & ti & (character id 9) & (URL of t) & (character id 10)
              end repeat
            end try
          end repeat
        end tell
        return out
        """
        let (out, err) = TabGuard.osascript(list)
        if err.contains("-1743") || err.contains("Not authorized") {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.deniedReported.insert(b.bundleID).inserted else { return }
                self.onDenied?(b.name)
            }
            return
        }
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let wi = Int(parts[0]), let ti = Int(parts[1]) else { continue }
            let url = String(parts[2])
            guard let host = URL(string: url)?.host, Defaults.isBlocked(host: host, sites: sites) else { continue }
            let target = TabGuard.escape(page(host))
            let set = "tell application id \"\(b.bundleID)\" to set URL of tab \(ti) of window \(wi) to \"\(target)\""
            let (_, e1) = TabGuard.osascript(set)
            if !e1.isEmpty {
                // Если браузер не умеет менять адрес вкладки — просто закрыть её.
                _ = TabGuard.osascript("tell application id \"\(b.bundleID)\" to close tab \(ti) of window \(wi)")
            }
        }
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func osascript(_ script: String) -> (String, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return ("", "\(error)") }
        // Не ждать вечно, если браузер завис.
        let deadline = DispatchTime.now() + 5
        DispatchQueue.global().asyncAfter(deadline: deadline) { if p.isRunning { p.terminate() } }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }

    // MARK: Block page

    /// Адрес страницы блокировки внутри приложения со списком задач.
    private func blockPageURL(_ s: Snapshot) -> (String) -> String {
        let file = Bundle.main.url(forResource: "blocked", withExtension: "html")
        let tasks = s.lockingTasks.prefix(5).map { t -> String in
            let late = t.isOverdue(at: s.now) ? "late" : ""
            return "\(t.title)|\(Fmt.deadline(t.deadline, now: s.now))|\(late)"
        }
        return { host in
            guard let file = file, var c = URLComponents(url: file, resolvingAgainstBaseURL: false) else {
                return "about:blank"
            }
            c.queryItems = [URLQueryItem(name: "site", value: host)] + tasks.map { URLQueryItem(name: "t", value: $0) }
            return c.url?.absoluteString ?? "about:blank"
        }
    }
}
