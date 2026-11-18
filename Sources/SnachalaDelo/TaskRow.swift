import SwiftUI
import Shared

struct TaskRow: View {
    @ObservedObject var model: Model
    var task: TaskItem

    @State private var rescheduling = false
    @State private var newDate = Date()
    @State private var hover = false

    var body: some View {
        let now = model.now
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                HoldCircle(done: task.isDone) { model.complete(task) }
                    .disabled(task.isDone)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(Theme.body(14, .medium))
                        .strikethrough(task.isDone, color: Theme.fg3)
                        .foregroundColor(task.isDone ? Theme.fg3 : Theme.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        tag(now)
                        Text(meta(now)).font(metaFont(now)).foregroundColor(metaColor(now))
                    }
                }
                Spacer(minLength: 4)
                if let d = task.deleteAt {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("удалится через \(Fmt.countdown(d, now: now))")
                            .font(Theme.body(12, .semibold).monospacedDigit()).foregroundColor(Theme.warn)
                        Button("Отменить") { model.cancelDelete(task) }
                            .buttonStyle(QuietButtonStyle())
                    }
                } else {
                    Menu {
                        if !task.isDone {
                            Button("Перенести дедлайн…") {
                                newDate = max(task.deadline, Date()).addingTimeInterval(3600)
                                if task.rescheduleCount >= 1 { newDate = min(newDate, limit) }
                                rescheduling = true
                            }
                        }
                        Button(task.isDone ? "Убрать из списка" : "Удалить…") { model.requestDelete(task) }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 22)
                    .opacity(hover ? 1 : 0.3)
                }
            }
            if rescheduling { rescheduleBox }
        }
        .padding(.vertical, 10).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(hover ? Theme.surface2 : .clear))
        .onHover { hover = $0 }
    }

    private var limit: Date { Date().addingTimeInterval(Rules.laterRescheduleLimit) }

    private var rescheduleBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            if task.rescheduleCount >= 1 {
                Text("Эту задачу уже переносили. Теперь можно отодвинуть не дальше чем на сутки.")
                    .font(Theme.body(12.5)).foregroundColor(Theme.warn).fixedSize(horizontal: false, vertical: true)
                DatePicker("", selection: $newDate, in: Date()...limit, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field).environment(\.locale, Fmt.ru)
            } else {
                Text("Перенести можно один раз. Потом только на сутки.")
                    .font(Theme.body(12.5)).foregroundColor(Theme.fg3)
                DatePicker("", selection: $newDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field).environment(\.locale, Fmt.ru)
            }
            HStack(spacing: 12) {
                Button("Перенести") { model.reschedule(task, to: newDate); rescheduling = false }
                    .buttonStyle(InkButtonStyle())
                Button("Отмена") { rescheduling = false }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
        .padding(.leading, 42)
    }

    @ViewBuilder private func tag(_ now: Date) -> some View {
        if task.isDone {
            Tag(text: "сделано", fg: Theme.free, bg: Theme.freeSoft)
        } else if task.isOverdue(at: now) {
            Tag(text: "просрочено", fg: .white, bg: Theme.lock)
        } else if task.isLocking(at: now) {
            Tag(text: "блокирует", fg: Theme.lock, bg: Theme.lockSoft)
        } else {
            Tag(text: "ждёт", fg: Theme.fg3, bg: Theme.surface2, border: Theme.line)
        }
    }

    private func meta(_ now: Date) -> String {
        if let d = task.doneAt { return "закрыта \(Fmt.deadline(d, now: now).replacingOccurrences(of: " к ", with: " в "))" }
        return "\(Fmt.deadline(task.deadline, now: now)) · \(Fmt.left(task.deadline, now: now))"
    }

    private func metaColor(_ now: Date) -> Color {
        if task.isDone { return Theme.fg3 }
        if task.isOverdue(at: now) { return Theme.lock }
        if task.deadline.timeIntervalSince(now) < 3 * 3600 { return Theme.warn }
        return Theme.fg3
    }

    private func metaFont(_ now: Date) -> Font {
        if task.isDone { return Theme.body(12.5) }
        if task.isOverdue(at: now) { return Theme.body(12.5, .bold) }
        if task.deadline.timeIntervalSince(now) < 3 * 3600 { return Theme.body(12.5, .semibold) }
        return Theme.body(12.5)
    }
}

struct Tag: View {
    var text: String
    var fg: Color
    var bg: Color
    var border: Color? = nil
    var body: some View {
        Text(text.uppercased())
            .font(Theme.body(10.5, .bold))
            .tracking(0.4)
            .padding(.horizontal, 7).padding(.vertical, 1.5)
            .foregroundColor(fg)
            .background(RoundedRectangle(cornerRadius: 5).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(border ?? .clear))
    }
}

/// Кружок, который надо удерживать 2 секунды.
struct HoldCircle: View {
    var done: Bool
    var onComplete: () -> Void
    @State private var progress: CGFloat = 0
    @State private var fired = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: done || fired ? 1 : progress)
                .stroke(Theme.free, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if done || fired {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundColor(Theme.free)
            }
        }
        .frame(width: 30, height: 30)
        .contentShape(Circle())
        // Вариант с pressing: работает на macOS 12.
        .onLongPressGesture(minimumDuration: 2, maximumDistance: 40, pressing: { pressing in
            guard !done, !fired else { return }
            if pressing {
                withAnimation(.linear(duration: 2)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }, perform: {
            fired = true
            onComplete()
        })
        .help(done ? "Сделано" : "Зажми, чтобы закрыть задачу")
    }
}
