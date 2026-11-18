import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Shared

struct SettingsView: View {
    @ObservedObject var model: Model
    @State private var newSite = ""

    private var locked: Bool { model.snapshot?.hasLockingTasks ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if locked {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").foregroundColor(Palette.lock)
                    Text("Пока есть срочные задачи, списки можно только пополнять.")
                }
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.lock.opacity(0.12)))
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Сайты").font(.headline)
                    Text("Во всех браузерах, включая инкогнито.").font(.caption).foregroundColor(.secondary)
                    List {
                        ForEach(model.snapshot?.sites ?? [], id: \.self) { s in
                            HStack {
                                Text(s)
                                Spacer()
                                Button { model.removeSite(s) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless).disabled(locked)
                            }
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                    HStack {
                        TextField("например, ivi.ru", text: $newSite).onSubmit(addSite)
                        Button("Добавить", action: addSite).disabled(newSite.isEmpty)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Приложения").font(.headline)
                    Text("Закрываются сразу при запуске.").font(.caption).foregroundColor(.secondary)
                    List {
                        ForEach(model.snapshot?.apps ?? []) { a in
                            HStack {
                                Text(a.name)
                                Spacer()
                                Button { model.removeApp(a) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless).disabled(locked)
                            }
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                    Button("Добавить приложение…", action: pickApp)
                }
            }

            if let e = model.error {
                Text(e).font(.callout).foregroundColor(Palette.warn)
            }
            Text("Почта, документы, поиск и сайты школы не трогаются: блокируется только то, что в списках. Задачи хранятся только на этом Маке.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 620, height: 500)
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
