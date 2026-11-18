import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Shared

struct SettingsView: View {
    @ObservedObject var model: Model
    @State private var newSite = ""

    private var locked: Bool { model.snapshot?.hasLockingTasks ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if locked {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Theme.lock)
                        Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    }
                    .frame(width: 26, height: 26)
                    Text("Пока есть срочные задачи, списки можно только пополнять.")
                        .font(Theme.body(13.5, .medium)).foregroundColor(Theme.fg)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.lockSoft))
            }

            HStack(alignment: .top, spacing: 16) {
                card(title: "Сайты", note: "Во всех браузерах, включая инкогнито.") {
                    rows(model.snapshot?.sites ?? [], label: { siteLabel($0) }, remove: { model.removeSite($0) })
                    HStack(spacing: 8) {
                        TextField("сайт или слово, напр. ivi.ru", text: $newSite)
                            .textFieldStyle(.plain)
                            .font(Theme.body(13))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface2))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
                            .onSubmit(addSite)
                        Button("Добавить", action: addSite)
                            .buttonStyle(InkButtonStyle())
                            .disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Слово без точки (например, lordfilm) блокирует все сайты, в адресе которых оно есть: так закрываются зеркала пиратских кинотеатров.")
                        .font(Theme.body(12)).foregroundColor(Theme.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                card(title: "Приложения", note: "Закрываются сразу при запуске.") {
                    rows(model.snapshot?.apps ?? [], label: { Text($0.name) }, remove: { model.removeApp($0) })
                    Button("Добавить приложение…", action: pickApp)
                        .buttonStyle(OutlineButtonStyle())
                }
            }

            if let e = model.error {
                Text(e).font(Theme.body(13)).foregroundColor(Theme.warn)
            }
            Text("Почта, документы, поиск и сайты школы не трогаются: блокируется только то, что в списках. Задачи хранятся только на этом Маке.")
                .font(Theme.body(12.5)).foregroundColor(Theme.fg3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 660, height: 540)
        .background(Theme.bg)
    }

    @ViewBuilder private func siteLabel(_ s: String) -> some View {
        if s.contains(".") {
            Text(s)
        } else {
            HStack(spacing: 6) {
                Text(s)
                Text("СЛОВО").font(Theme.body(9.5, .bold)).tracking(0.4)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .foregroundColor(Theme.fg3)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line))
            }
        }
    }

    private func card<C: View>(title: String, note: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.display(15.5, .bold)).foregroundColor(Theme.fg)
            Text(note).font(Theme.body(12.5)).foregroundColor(Theme.fg3)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }

    private func rows<T: Hashable, L: View>(_ items: [T], @ViewBuilder label: @escaping (T) -> L,
                                             remove: @escaping (T) -> Void) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(items, id: \.self) { item in
                    HStack {
                        label(item).font(Theme.body(13)).foregroundColor(Theme.fg)
                        Spacer()
                        Button { remove(item) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .foregroundColor(Theme.fg3)
                            .disabled(locked)
                            .opacity(locked ? 0.35 : 1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface2))
                }
            }
        }
        .frame(height: 250)
    }

    private func addSite() {
        let s = newSite.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        model.addSite(s)
        newSite = ""
    }

    private func pickApp() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowsMultipleSelection = true
        p.prompt = "Блокировать"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK else { return }
        for url in p.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
            let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
            model.addApp(BlockedApp(bundleID: id, name: name))
        }
    }
}
