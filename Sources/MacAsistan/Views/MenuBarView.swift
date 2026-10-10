import SwiftUI

/// Menü çubuğu simgesine tıklayınca açılan küçük panel.
struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    private var settings: AppSettings { app.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                Text(L10n.t(.appName)).font(.headline)
                Spacer()
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }

            // Dinle / durdur
            Button {
                app.toggleListening()
            } label: {
                HStack {
                    Image(systemName: app.speechIn.mode == .command ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                    Text(app.speechIn.mode == .command ? L10n.t(.stopListening) : L10n.t(.startListening))
                    Spacer()
                    Text("⌥Space").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(app.speechIn.mode == .command ? .red : .accentColor)
            .controlSize(.large)

            if app.speechIn.mode == .command, !app.speechIn.transcript.isEmpty {
                Text(app.speechIn.transcript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if app.speechOut.isSpeaking {
                Button {
                    app.stopSpeaking()
                } label: {
                    Label(L10n.t(.stopSpeaking), systemImage: "speaker.slash.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            // Konuşma tanıma dili – tek tıkla
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(.speechLanguage)).font(.caption).foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { settings.speechLanguage }, set: { settings.speechLanguage = $0 })) {
                    ForEach(SpeechLanguage.allCases) { language in
                        Text(language.shortLabel).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle(L10n.t(.wakeWord), isOn: Binding(get: { settings.wakeWordEnabled }, set: { settings.wakeWordEnabled = $0 }))
            Toggle(L10n.t(.readAloud), isOn: Binding(get: { settings.readAloud }, set: { settings.readAloud = $0 }))
            HStack {
                Toggle(L10n.t(.evidenceMode), isOn: Binding(get: { settings.evidenceMode }, set: { settings.evidenceMode = $0 }))
                Spacer()
                Button {
                    show("library")
                } label: {
                    Image(systemName: "books.vertical")
                }
                .help(L10n.t(.library))
            }

            Divider()

            // Sağlayıcı ve model
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(.provider)).font(.caption).foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { settings.providerSelection }, set: { settings.providerSelection = $0 })) {
                    Text("✨ \(L10n.t(.automatic))").tag("auto")
                    Divider()
                    ForEach(settings.allProviders, id: \.self) { ref in
                        Text(settings.displayName(ref)).tag(ref.rawValue)
                    }
                }
                .labelsHidden()
                Text(settings.autoSelect
                     ? "\(L10n.t(.preferredProvider)): \(settings.displayName(settings.provider)) · \(settings.currentModel)"
                     : "\(L10n.t(.model)): \(settings.currentModel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !app.hasKeyForCurrentProvider {
                    Label(L10n.t(.keyNotSet), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let last = lastAnswer {
                Divider()
                Text(last)
                    .font(.callout)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            Divider()

            HStack {
                Button(L10n.t(.openChat)) { show("chat") }
                Spacer()
                Button {
                    show("settings")
                } label: {
                    Image(systemName: "gearshape")
                }
                .help(L10n.t(.settings))
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help(L10n.t(.quit))
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var statusText: String {
        if app.isSending { return L10n.t(.thinking) }
        if app.speechOut.isSpeaking { return L10n.t(.speaking) }
        switch app.speechIn.mode {
        case .command: return L10n.t(.listening)
        case .wake, .bargeIn: return L10n.t(.wakeWaiting)
        case .off: return L10n.t(.idle)
        }
    }

    private var lastAnswer: String? {
        guard let message = app.store.selected?.messages.last(where: { $0.role == .assistant && !$0.isError }) else { return nil }
        return message.text
    }

    private func show(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}
