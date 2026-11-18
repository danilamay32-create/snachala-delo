import SwiftUI
import Shared

enum Palette {
    static let lock = Color(nsColor: .systemRed)
    static let free = Color(nsColor: .systemGreen)
    static let warn = Color(nsColor: .systemOrange)
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
        VStack(alignment: .leading, spacing: 12) {
            StatusCard(model: model)
            addBox
            if let e = model.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(Palette.warn)
                    Text(e).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
            }
            HStack {
                Text("ЗАДАЧИ").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Spacer()
                let open = tasks.filter { !$0.isDone }.count
                if open > 0 { Text("\(open) открыто").font(.caption).foregroundColor(.secondary) }
            }
            if tasks.isEmpty {
                Text("Пока пусто. Впиши задачу и выбери дедлайн. Блокировка включится, когда до дедлайна останется меньше суток.")
                    .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(tasks) { t in
                            TaskRow(model: model, task: t)
                        }
                    }
                }
                .frame(height: min(CGFloat(tasks.count) * 60 + 8, 330))
                Text("Чтобы закрыть задачу, зажми кружок на 2 секунды.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Divider()
            HStack {
                Button("Настройки…", action: openSettings)
                Spacer()
                Button("Скрыть значок", action: quit)
                    .help("Значок пропадёт до следующего входа. Блокировка всё равно работает.")
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 380)
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

    private var addBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Что нужно сделать?", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onSubmit(submit)
            HStack(spacing: 6) {
                ForEach([Quick.twoHours, .tonight, .tomorrow]) { q in chip(q) }
            }
            HStack(spacing: 6) {
                chip(.threeDays)
                Chip(label: "Своя дата", on: custom) { custom.toggle(); if custom { quick = nil } }
                Spacer()
                Button("Добавить", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || chosenDate == nil)
            }
            if custom {
                DatePicker("Дедлайн", selection: $customDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.field)
                    .environment(\.locale, Fmt.ru)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
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
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .foregroundColor(on ? Color(nsColor: .textBackgroundColor) : .primary)
                .background(Capsule().fill(on ? Color.primary : Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

struct StatusCard: View {
    @ObservedObject var model: Model
    @State private var armed = false

    var body: some View {
        let s = model.snapshot
        let now = model.now
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(color)
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 14, weight: .bold))
                Text(subtitle(s, now)).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if model.status == .locked, let s = s {
                if s.passAvailableToday {
                    Button(armed ? "Точно?" : "15 минут") {
                        if armed { model.startPass(); armed = false } else {
                            armed = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { armed = false }
                        }
                    }
                    .help("Передышка: всё откроется на 15 минут. Один раз в день.")
                } else {
                    Text("Передышка\nзавтра").font(.caption2).multilineTextAlignment(.trailing).foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.14)))
    }

    private var color: Color {
        switch model.status {
        case .locked: return Palette.lock
        case .pass: return Palette.warn
        case .free: return Palette.free
        case .offline: return .gray
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
        case .free: return "Всё открыто"
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
            let more = l.count > 1 ? " и ещё \(l.count - 1)" : ""
            return "Сначала «\(first.title)»\(more)"
        case .pass:
            if let p = s.passUntil { return "Всё открыто ещё \(Fmt.countdown(p, now: now))" }
            return ""
        case .free:
            let next = s.tasks.filter { !$0.isDone }.min { $0.deadline < $1.deadline }
            if let n = next {
                let start = n.deadline.addingTimeInterval(-Rules.lockWindow)
                return "Блокировка начнётся \(Fmt.deadline(start, now: now).replacingOccurrences(of: " к ", with: " в "))"
            }
            return "Срочных задач нет"
        case .offline:
            return ""
        }
    }
}
