import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var tab: Tab = .ai

    enum Tab: Hashable { case general, ai, voice, data, about }

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab()
                .tabItem { Label(L10n.t(.tabGeneral), systemImage: "gearshape") }
                .tag(Tab.general)
            AITab()
                .tabItem { Label(L10n.t(.tabAI), systemImage: "brain") }
                .tag(Tab.ai)
            VoiceTab()
                .tabItem { Label(L10n.t(.tabVoice), systemImage: "waveform") }
                .tag(Tab.voice)
            DataTab()
                .tabItem { Label(L10n.t(.tabData), systemImage: "externaldrive") }
                .tag(Tab.data)
            AboutTab()
                .tabItem { Label(L10n.t(.tabAbout), systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .padding(16)
        .frame(width: 620, height: 520)
        .navigationTitle(L10n.t(.settings))
    }
}

// MARK: - Genel

private struct GeneralTab: View {
    @EnvironmentObject var app: AppState
    private var settings: AppSettings { app.settings }

    var body: some View {
        Form {
            Picker(L10n.t(.uiLanguage), selection: Binding(get: { settings.uiLanguage }, set: { settings.uiLanguage = $0 })) {
                ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
            }
            Toggle(L10n.t(.readAloud), isOn: Binding(get: { settings.readAloud }, set: { settings.readAloud = $0 }))
            VStack(alignment: .leading, spacing: 2) {
                Toggle(L10n.t(.hotkey), isOn: Binding(get: { settings.hotkeyEnabled }, set: { settings.hotkeyEnabled = $0 }))
                Text(L10n.t(.hotkeyHint)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Yapay zekâ

private struct AITab: View {
    @EnvironmentObject var app: AppState
    private var settings: AppSettings { app.settings }

    @State private var loadedModels: [AIProviderKind: [String]] = [:]
    @State private var loading = false
    @State private var info: String?

    var body: some View {
        Form {
            if app.apiKeys.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t(.welcomeTitle)).font(.headline)
                        Text(L10n.t(.welcomeText)).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Picker(L10n.t(.provider), selection: Binding(get: { settings.provider }, set: { settings.provider = $0 })) {
                    ForEach(AIProviderKind.allCases) { Text($0.displayName).tag($0) }
                }
                HStack {
                    TextField(L10n.t(.model), text: Binding(
                        get: { settings.currentModel },
                        set: { settings.setModel($0, for: settings.provider) }
                    ))
                    Menu {
                        let models = loadedModels[settings.provider] ?? settings.provider.suggestedModels
                        ForEach(models, id: \.self) { model in
                            Button(model) { settings.setModel(model, for: settings.provider) }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Button(L10n.t(.loadModels)) { Task { await loadModels() } }
                        .disabled(loading || app.apiKeys[settings.provider] == nil)
                }
                if let info {
                    Text(info).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L10n.t(.modelHint)).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(AIProviderKind.allCases) { kind in
                    APIKeyRow(kind: kind)
                }
            } header: {
                Text(L10n.t(.apiKeys))
            } footer: {
                Label(L10n.t(.keySavedInKeychain), systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func loadModels() async {
        loading = true
        defer { loading = false }
        let kind = settings.provider
        do {
            let models = try await app.listModels(for: kind)
            loadedModels[kind] = models.isEmpty ? kind.suggestedModels : models
            info = "\(models.count) \(L10n.t(.modelsLoaded))"
        } catch {
            info = "\(L10n.t(.errorPrefix)): \(error.localizedDescription)"
        }
    }
}

private struct APIKeyRow: View {
    @EnvironmentObject var app: AppState
    let kind: AIProviderKind
    @State private var input = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(kind.displayName).frame(width: 140, alignment: .leading)
                SecureField(L10n.t(.apiKeyPlaceholder), text: $input)
                    .onSubmit(save)
                Button(L10n.t(.save), action: save)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                if app.apiKeys[kind] != nil {
                    Button(role: .destructive) {
                        app.deleteKey(for: kind)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help(L10n.t(.delete))
                }
            }
            HStack {
                if app.apiKeys[kind] != nil {
                    Text(L10n.t(.keyStored)).foregroundStyle(.green)
                } else {
                    Text(L10n.t(.keyMissing)).foregroundStyle(.secondary)
                }
                Link(kind.keyHelpURL.host ?? "", destination: kind.keyHelpURL)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .font(.caption)
        }
    }

    private func save() {
        do {
            try app.saveKey(input, for: kind)
            input = ""
            error = nil
            if app.apiKeys[app.settings.provider] == nil { app.settings.provider = kind }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Ses

private struct VoiceTab: View {
    @EnvironmentObject var app: AppState
    private var settings: AppSettings { app.settings }

    var body: some View {
        Form {
            Section {
                Picker(L10n.t(.speechLanguage), selection: Binding(get: { settings.speechLanguage }, set: { settings.speechLanguage = $0 })) {
                    ForEach(SpeechLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                Text(app.speechIn.onDeviceAvailable ? L10n.t(.onDeviceYes) : L10n.t(.onDeviceNo))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(L10n.t(.wakeWord), isOn: Binding(get: { settings.wakeWordEnabled }, set: { settings.wakeWordEnabled = $0 }))
                    Text(L10n.t(.wakeWordHint)).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text(L10n.t(.silenceDelay))
                    Slider(value: Binding(get: { settings.silenceSeconds }, set: { settings.silenceSeconds = $0 }), in: 0.8...4, step: 0.1)
                    Text(String(format: "%.1f %@", settings.silenceSeconds, L10n.t(.seconds)))
                        .monospacedDigit()
                        .frame(width: 50)
                }
            }

            Section(L10n.t(.voicesTitle)) {
                Toggle(L10n.t(.readAloud), isOn: Binding(get: { settings.readAloud }, set: { settings.readAloud = $0 }))
                ForEach(["tr", "de", "en"], id: \.self) { code in
                    HStack {
                        Text(code.uppercased()).bold().frame(width: 30, alignment: .leading)
                        Text(SpeechOutput.voiceDescription(for: code) ?? L10n.t(.voiceNotFound))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            app.speechOut.speak(sample(code), fallbackLanguage: code)
                        } label: {
                            Image(systemName: "play.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section(L10n.t(.permissions)) {
                permissionRow(L10n.t(.permMic), status: micStatusText)
                permissionRow(L10n.t(.permSpeech), status: speechStatusText)
                HStack {
                    Button(L10n.t(.requestPermissions)) {
                        Task { await app.speechIn.requestPermissions() }
                    }
                    Button(L10n.t(.openPrivacySettings)) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { app.speechIn.refreshPermissionStatus() }
    }

    private func sample(_ code: String) -> String {
        switch code {
        case "tr": return "Merhaba, ben Mac Asistan. Sana nasıl yardımcı olabilirim?"
        case "de": return "Hallo, ich bin Mac Asistan. Wie kann ich dir helfen?"
        default: return "Hello, I'm Mac Asistan. How can I help you?"
        }
    }

    private func permissionRow(_ title: String, status: (String, Color)) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(status.0).foregroundStyle(status.1)
        }
    }

    private var micStatusText: (String, Color) {
        switch app.speechIn.micStatus {
        case .authorized: return (L10n.t(.permGranted), .green)
        case .denied, .restricted: return (L10n.t(.permDenied), .red)
        default: return (L10n.t(.permUnknown), .secondary)
        }
    }

    private var speechStatusText: (String, Color) {
        switch app.speechIn.speechStatus {
        case .authorized: return (L10n.t(.permGranted), .green)
        case .denied, .restricted: return (L10n.t(.permDenied), .red)
        default: return (L10n.t(.permUnknown), .secondary)
        }
    }
}

// MARK: - Veriler

private struct DataTab: View {
    @EnvironmentObject var app: AppState
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                Text(L10n.t(.historyLocation))
                Text(app.store.folderURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Button(L10n.t(.openFolder)) {
                        try? FileManager.default.createDirectory(at: app.store.folderURL, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(app.store.folderURL)
                    }
                    Spacer()
                    Button(L10n.t(.clearHistory), role: .destructive) { confirmDelete = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(L10n.t(.clearHistoryConfirm), isPresented: $confirmDelete) {
            Button(L10n.t(.clearHistory), role: .destructive) { app.store.deleteAll() }
            Button(L10n.t(.cancel), role: .cancel) {}
        }
    }
}

// MARK: - Hakkında

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(L10n.t(.appName)).font(.title.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text(L10n.t(.aboutText))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
