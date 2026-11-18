import Foundation

enum Fmt {
    static let ru = Locale(identifier: "ru_RU")

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = ru
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// «сегодня к 22:00», «завтра к 18:00», «в пт, 21 нояб. к 10:00»
    static func deadline(_ d: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: now) { return "сегодня к \(time(d))" }
        if let tmr = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: tmr) {
            return "завтра к \(time(d))"
        }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(d, inSameDayAs: y) {
            return "вчера к \(time(d))"
        }
        let f = DateFormatter()
        f.locale = ru
        f.dateFormat = "EE, d MMM к HH:mm"
        return f.string(from: d)
    }

    /// «через 3 ч 20 мин», «через 12 мин», «просрочено на 2 ч»
    static func left(_ d: Date, now: Date = Date()) -> String {
        let s = d.timeIntervalSince(now)
        let a = abs(Int(s))
        let days = a / 86400, h = (a % 86400) / 3600, m = (a % 3600) / 60
        let body: String
        if days > 0 { body = h > 0 ? "\(days) д \(h) ч" : "\(days) д" }
        else if h > 0 { body = m > 0 ? "\(h) ч \(m) мин" : "\(h) ч" }
        else { body = "\(max(m, 1)) мин" }
        return s >= 0 ? "через \(body)" : "просрочено на \(body)"
    }

    static func countdown(_ d: Date, now: Date = Date()) -> String {
        let s = max(0, Int(d.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

enum Quick: CaseIterable, Identifiable {
    case twoHours, tonight, tomorrow, threeDays
    var id: Self { self }

    var label: String {
        switch self {
        case .twoHours: return "Через 2 часа"
        case .tonight: return "Сегодня к 22:00"
        case .tomorrow: return "Завтра к 18:00"
        case .threeDays: return "Через 3 дня"
        }
    }

    func date(from now: Date = Date()) -> Date? {
        let cal = Calendar.current
        switch self {
        case .twoHours:
            return now.addingTimeInterval(2 * 3600)
        case .tonight:
            let d = cal.date(bySettingHour: 22, minute: 0, second: 0, of: now)!
            return d > now.addingTimeInterval(10 * 60) ? d : nil
        case .tomorrow:
            let t = cal.date(byAdding: .day, value: 1, to: now)!
            return cal.date(bySettingHour: 18, minute: 0, second: 0, of: t)
        case .threeDays:
            let t = cal.date(byAdding: .day, value: 3, to: now)!
            return cal.date(bySettingHour: 18, minute: 0, second: 0, of: t)
        }
    }
}
