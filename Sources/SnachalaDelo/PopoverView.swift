import SwiftUI
import Shared

enum Palette {
    static let lock = Theme.lock
    static let free = Theme.free
    static let warn = Theme.warn
}

struct PopoverView: View {
    @ObservedObject var model: Model
    var openSettings: () -> Void
    var quit: () -> Void

    @State private var title = ""
    @State private var quick: Quick?
    @State private var custom = false
    @State private var customDate = Calendar.current.date(byAdding: .hour, value: 3, to: Date())!

    private var tasks: [TaskItem] { model.snapshot?.tasks ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusCard(model: model)
                .padding(16)
            addBox
                .padding(.horizontal, 16)
            if let e = model.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(Theme.warn)
                    Text(e).font(Theme.body(13)).foregroundColor(Theme.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.error = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(QuietButtonStyle())
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warnSoft))
                .padding(.horizontal, 16).padding(.top, 10)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("ЗАДАЧИ").font(Theme.body(11.5, .semibold)).tracking(1.2).foregroundColor(Theme.fg3)
                Spacer()
                let open = tasks.filter { !$0.isDone }.count
                if open > 0 {
                    Text("\(open) \(Plural.ru(open, "открыта", "открыты", "открыто"))")
                        .font(Theme.body(11.5, .semibold)).tracking(1.2).foregroundColor(Theme.fg3)
                }
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 6)

            if tasks.isEmpty {
                Text("Пусто. Впиши первую задачу сверху. Блокировка включится, когда до дедлайна останется меньше суток.")
                    .font(Theme.body(13.5)).foregroundColor(Theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(tasks) { t in
                            TaskRow(model: model, task: t)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: min(CGFloat(tasks.count) * 60 + 8, 330))
                Text("Чтобы закрыть задачу, зажми кружок на 2 секунды. Случайно или сгоряча не закроешь.")
                    .font(Theme.body(12.5)).foregroundColor(Theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.top, 2)
            }

            Rectangle().fill(Theme.line).frame(height: 1).padding(.top, 14)
            HStack {
                Button(action: openSettings) {
                    Label("Настройки", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Скрыть значок", action: quit)
                    .buttonStyle(QuietButtonStyle())
                    .help("Значок пропадёт до следующего входа. Блокировка всё равно работает.")
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Theme.surface2)
        }
        .frame(width: 400)
        .background(Theme.surface)
    }

    private var chosenDate: Date? {
        custom ? customDate : quick?.date()
    }

    private func submit() {
        guard let d = chosenDate else { model.error = "Выбери дедлайн"; return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        model.add(t, d)
        title = ""
        quick = nil
        custom = false
    }

    @FocusState private var fieldFocused: Bool

    private var addBox: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("Что нужно сделать? Например, реферат по истории", text: $title)
                .textFieldStyle(.plain)
                .font(Theme.body(15))
                .foregroundColor(Theme.fg)
                .focused($fieldFocused)
                .onSubmit(submit)
            HStack(spacing: 6) {
                ForEach([Quick.twoHours, .tonight, .tomorrow]) { q in chip(q) }
            }
            HStack(spacing: 6) {
                chip(.threeDays)
                Chip(label: "Своя дата", on: custom) { custom.toggle(); if custom { quick = nil } }
                Spacer()
                Button("Добавить", action: submit)
                    .buttonStyle(InkButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || chosenDate == nil)
            }
            if custom {
                DatePicker("Дедлайн", selection: $customDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.field)
                    .font(Theme.body(13))
                    .environment(\.locale, Fmt.ru)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(fieldFocused ? Theme.fg2 : Theme.line, lineWidth: 1.5))
    }

    private func chip(_ q: Quick) -> some View {
        Chip(label: q.label, on: quick == q && !custom) {
            quick = q
            custom = false
        }
        .disabled(q.date() == nil)
    }
}

struct Chip: View {
    var label: String
    var on: Bool
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.body(12.5, .medium))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .foregroundColor(on ? Theme.surface : Theme.fg2)
                .background(Capsule().fill(on ? Theme.fg : Theme.surface2))
                .overlay(Capsule().stroke(on ? Theme.fg : Theme.line))
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}

enum Plural {
    /// ru(1, "задача", "задачи", "задач")
    static func ru(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m10 = n % 10, m100 = n % 100
        if m10 == 1 && m100 != 11 { return one }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return few }
        return many
    }
}

struct StatusCard: View {
    @ObservedObject var model: Model
    @State private var armed = false

    var body: some View {
        let s = model.snapshot
        let now = model.now
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(accent)
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline).font(Theme.display(16, .bold)).foregroundColor(Theme.fg)
                Text(subtitle(s, now)).font(Theme.body(13)).foregroundColor(Theme.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if model.status == .locked, let s = s {
                if s.passAvailableToday {
                    Button(armed ? "Точно? Ещё раз" : "Передышка 15 мин") {
                        if armed { model.startPass(); armed = false } else {
                            armed = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { armed = false }
                        }
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .help("Всё откроется на 15 минут. Один раз в день.")
                } else {
                    Button("Передышка уже была") {}
                        .buttonStyle(OutlineButtonStyle())
                        .disabled(true)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 12).fill(soft))
        .animation(.easeInOut(duration: 0.35), value: model.status)
    }

    private var accent: Color {
        switch model.status {
        case .locked: return Theme.lock
        case .pass: return Theme.warn
        case .free: return Theme.free
        case .offline: return Theme.fg3
        }
    }

    private var soft: Color {
        switch model.status {
        case .locked: return Theme.lockSoft
        case .pass: return Theme.warnSoft
        case .free: return Theme.freeSoft
        case .offline: return Theme.surface2
        }
    }

    private var icon: String {
        switch model.status {
        case .locked: return "lock.fill"
        case .pass: return "cup.and.saucer.fill"
        case .free: return "checkmark"
        case .offline: return "exclamationmark.triangle.fill"
        }
    }

    private var headline: String {
        switch model.status {
        case .locked: return "Сериалы закрыты"
        case .pass: return "Передышка"
        case .free: return "Свободна"
        case .offline: return "Служба не запущена"
        }
    }

    private func subtitle(_ s: Snapshot?, _ now: Date) -> String {
        guard let s = s, model.online else {
            return "Блокировка сейчас не работает. Запусти установщик ещё раз."
        }
        switch model.status {
        case .locked:
            let l = s.lockingTasks
            guard let first = l.first else { return "" }
            if l.count == 1 {
                return "«\(first.title)» держит блокировку. Дедлайн \(Fmt.deadline(first.deadline, now: now))."
            }
            let verb = Plural.ru(l.count, "задача держит", "задачи держат", "задач держат")
            return "\(l.count) \(verb) блокировку. Ближайший дедлайн \(Fmt.deadline(first.deadline, now: now))."
        case .pass:
            if let p = s.passUntil { return "Всё открыто ещё \(Fmt.countdown(p, now: now)). Потом блокировка вернётся." }
            return ""
        case .free:
            let next = s.tasks.filter { !$0.isDone }.min { $0.deadline < $1.deadline }
            if let n = next {
                let start = n.deadline.addingTimeInterval(-Rules.lockWindow)
                let when = Fmt.deadline(start, now: now).replacingOccurrences(of: " к ", with: " в ")
                return "Срочных дел нет. Следующая задача начнёт блокировать \(when)."
            }
            return "Все задачи закрыты. Можно смотреть что угодно."
        case .offline:
            return ""
        }
    }
}
