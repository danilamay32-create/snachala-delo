import Foundation
import Darwin

/// Закрывает запрещённые приложения (и все их вспомогательные процессы).
final class AppKiller {
    private var bundleIDCache: [String: String?] = [:]
    /// pid → когда отправили SIGTERM
    private var terminated: [pid_t: Date] = [:]

    private func allPids() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let n = pids.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }
        return n > 0 ? Array(pids.prefix(Int(n))).filter { $0 > 0 } : []
    }

    private func path(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * 1024)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    /// «/Applications/IINA.app/Contents/MacOS/IINA» → «/Applications/IINA.app»
    static func outerBundle(of path: String) -> String? {
        guard let r = path.range(of: ".app/") else { return nil }
        return String(path[..<r.lowerBound]) + ".app"
    }

    private func bundleID(at bundlePath: String) -> String? {
        if let cached = bundleIDCache[bundlePath] { return cached }
        let plist = bundlePath + "/Contents/Info.plist"
        var id: String?
        if let data = FileManager.default.contents(atPath: plist),
           let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            id = obj["CFBundleIdentifier"] as? String
        }
        bundleIDCache[bundlePath] = id
        return id
    }

    /// Возвращает имена закрытых приложений (для лога).
    @discardableResult
    func enforce(blocked: Set<String>) -> [String] {
        guard !blocked.isEmpty else { terminated.removeAll(); return [] }
        let now = Date()
        var killed: [String] = []
        var alive = Set<pid_t>()
        for pid in allPids() {
            guard let p = path(of: pid), let bundle = AppKiller.outerBundle(of: p),
                  let id = bundleID(at: bundle), blocked.contains(id) else { continue }
            alive.insert(pid)
            if let sent = terminated[pid] {
                if now.timeIntervalSince(sent) > 3 { kill(pid, SIGKILL) }
            } else {
                kill(pid, SIGTERM)
                terminated[pid] = now
                killed.append((bundle as NSString).lastPathComponent)
            }
        }
        terminated = terminated.filter { alive.contains($0.key) }
        if !killed.isEmpty { log("closed: \(Set(killed).sorted().joined(separator: ", "))") }
        return killed
    }
}
