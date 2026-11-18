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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                HoldCircle(done: task.isDone) { model.complete(task) }
                    .disabled(task.isDone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .strikethrough(task.isDone)
                        .foregroundColor(task.isDone ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        tag(now)
                        Text(meta(now)).font(.caption).foregroundColor(metaColor(now))
                    }
                }
                Spacer(minLength: 4)
                if let d = task.deleteAt {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("удалится через \(Fmt.countdown(d, now: now))")
                            .font(.caption.monospacedDigit()).foregroundColor(Palette.warn)
                        Button("Отменить") { model.cancelDelete(task) }
                            .buttonStyle(.borderless).font(.caption)
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
                    .opacity(hover ? 1 : 0.35)
                }
            }
            if rescheduling { rescheduleBox }
        }
        .padding(.vertical, 7).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Color.secondary.opacity(0.08) : .clear))
        .onHover { hover = $0 }
    }

    private var limit: Date { Date().addingTimeInterval(Rules.laterRescheduleLimit) }

    private var rescheduleBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            if task.rescheduleCount >= 1 {
                Text("Эту задачу уже переносили. Теперь можно отодвинуть не дальше чем на сутки.")
                    .font(.caption).foregroundColor(Palette.warn).fixedSize(horizontal: false, vertical: true)
                DatePicker("", selection: $newDate, in: Date()...limit, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field).environment(\.locale, Fmt.ru)
            } else {
                Text("Перенести можно один раз. Потом только на сутки.")
                    .font(.caption).foregroundColor(.secondary)
                DatePicker("", selection: $newDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field).environment(\.locale, Fmt.ru)
            }
            HStack {
                Button("Перенести") { model.reschedule(task, to: newDate); rescheduling = false }
                Button("Отмена") { rescheduling = false }.buttonStyle(.borderless)
            }
            .font(.callout)
        }
        .padding(.leading, 34)
    }

    @ViewBuilder private func tag(_ now: Date) -> some View {
        if task.isDone {
            Tag(text: "сделано", fg: Palette.free, bg: Palette.free.opacity(0.15))
        } else if task.isOverdue(at: now) {
            Tag(text: "просрочено", fg: .white, bg: Palette.lock)
        } else if task.isLocking(at: now) {
            Tag(text: "блокирует", fg: Palette.lock, bg: Palette.lock.opacity(0.15))
        } else {
            Tag(text: "ждёт", fg: .secondary, bg: Color.secondary.opacity(0.12))
        }
    }

    private func meta(_ now: Date) -> String {
        if let d = task.doneAt { return "закрыта \(Fmt.deadline(d, now: now).replacingOccurrences(of: " к ", with: " в "))" }
        return "\(Fmt.deadline(task.deadline, now: now)) · \(Fmt.left(task.deadline, now: now))"
    }

    private func metaColor(_ now: Date) -> Color {
        if task.isDone { return .secondary }
        if task.isOverdue(at: now) { return Palette.lock }
        if task.deadline.timeIntervalSince(now) < 3 * 3600 { return Palette.warn }
        return .secondary
    }
}

struct Tag: View {
    var text: String
    var fg: Color
    var bg: Color
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .foregroundColor(fg)
            .background(RoundedRectangle(cornerRadius: 4).fill(bg))
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
            Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 2)
            Circle()
                .trim(from: 0, to: done || fired ? 1 : progress)
                .stroke(Palette.free, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if done || fired {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundColor(Palette.free)
            }
        }
        .frame(width: 24, height: 24)
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
        .help(done ? "Сделано" : "Зажми на 2 секунды, чтобы закрыть")
    }
}
