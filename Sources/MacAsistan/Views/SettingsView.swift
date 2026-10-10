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
            Toggle(L10n.t(.showInDock), isOn: Binding(get: { settings.showInDock }, set: { settings.showInDock = $0 }))
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

    @State private var loadedModels: [ProviderRef: [String]] = [:]
    @State private var loading = false
    @State private var info: String?

    var body: some View {
        Form {
            if app.apiKeys.isEmpty && settings.customProviders.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t(.welcomeTitle)).font(.headline)
                        Text(L10n.t(.welcomeText)).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(L10n.t(.autoSelect), isOn: Binding(get: { settings.autoSelect }, set: { settings.autoSelect = $0 }))
                    Text(L10n.t(.autoSelectHint)).font(.caption).foregroundStyle(.secondary)
                }
                Picker(settings.autoSelect ? L10n.t(.preferredProvider) : L10n.t(.provider),
                       selection: Binding(get: { settings.provider }, set: { settings.provider = $0; info = nil })) {
                    ForEach(settings.allProviders, id: \.self) { Text(settings.displayName($0)).tag($0) }
                }
                HStack {
                    TextField(L10n.t(.model), text: Binding(
                        get: { settings.currentModel },
                        set: { settings.setModel($0, for: settings.provider) }
                    ))
                    Menu {
                        let models = loadedModels[settings.provider] ?? settings.suggestedModels(settings.provider)
                        ForEach(models, id: \.self) { model in
                            Button(model) { settings.setModel(model, for: settings.provider) }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Button(L10n.t(.loadModels)) { Task { await loadModels() } }
                        .disabled(loading || !app.isUsable(settings.provider))
                }
                if let info {
                    Text(info).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L10n.t(.modelHint)).font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Picker(L10n.t(.speed), selection: Binding(get: { settings.responseSpeed }, set: { settings.responseSpeed = $0 })) {
                        Text(L10n.t(.speedFast)).tag(ResponseSpeed.fast)
                        Text(L10n.t(.speedBalanced)).tag(ResponseSpeed.balanced)
                        Text(L10n.t(.speedDeep)).tag(ResponseSpeed.deep)
                    }
                    .pickerStyle(.segmented)
                    Text(L10n.t(.speedHint)).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(AIProviderKind.allCases) { kind in
                    APIKeyRow(ref: .builtin(kind))
                }
            } header: {
                Text(L10n.t(.apiKeys))
            } footer: {
                Label(L10n.t(.keySavedInKeychain), systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(settings.customProviders) { provider in
                    CustomProviderRow(id: provider.id)
                }
                Menu {
                    ForEach(CustomProvider.presets, id: \.name) { preset in
                        Button(preset.name) { app.addCustomProvider(from: preset) }
                    }
                    Divider()
                    Button(L10n.t(.customOpenAI)) {
                        app.addCustomProvider(from: CustomProvider(name: L10n.t(.newAIName), baseURL: "https://", model: ""))
                    }
                } label: {
                    Label(L10n.t(.addAI), systemImage: "plus.circle.fill")
                }
                .fixedSize()
            } header: {
                Text(L10n.t(.otherAIs))
            } footer: {
                Text(L10n.t(.otherAIsHint)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func loadModels() async {
        loading = true
        defer { loading = false }
        let ref = settings.provider
        do {
            let models = try await app.listModels(for: ref)
            loadedModels[ref] = models.isEmpty ? settings.suggestedModels(ref) : models
            info = "\(models.count) \(L10n.t(.modelsLoaded))"
        } catch {
            info = "\(L10n.t(.errorPrefix)): \(error.localizedDescription)"
        }
    }
}

/// Kullanıcının eklediği bir yapay zekâ: ad, adres, model, anahtar.
private struct CustomProviderRow: View {
    @EnvironmentObject var app: AppState
    let id: UUID
    @State private var confirmRemove = false

    private var settings: AppSettings { app.settings }

    private func binding(_ keyPath: WritableKeyPath<CustomProvider, String>) -> Binding<String> {
        Binding(
            get: { settings.custom(id)?[keyPath: keyPath] ?? "" },
            set: { value in settings.updateCustom(id) { $0[keyPath: keyPath] = value } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(L10n.t(.name), text: binding(\.name))
                    .font(.headline)
                    .textFieldStyle(.plain)
                Spacer()
                Button(role: .destructive) {
                    confirmRemove = true
                } label: {
                    Label(L10n.t(.removeAI), systemImage: "minus.circle")
                }
                .controlSize(.small)
            }
            LabeledContent(L10n.t(.baseURL)) {
                TextField("https://…/v1", text: binding(\.baseURL))
                    .font(.system(.body, design: .monospaced))
            }
            LabeledContent(L10n.t(.model)) {
                TextField("model-id", text: binding(\.model))
                    .font(.system(.body, design: .monospaced))
            }
            Toggle(L10n.t(.keyRequired), isOn: Binding(
                get: { settings.custom(id)?.requiresKey ?? true },
                set: { value in settings.updateCustom(id) { $0.requiresKey = value } }
            ))
            .controlSize(.small)
            APIKeyRow(ref: .custom(id), showName: false)
        }
        .padding(.vertical, 4)
        .confirmationDialog(L10n.t(.removeAIConfirm), isPresented: $confirmRemove) {
            Button(L10n.t(.removeAI), role: .destructive) { app.removeCustomProvider(id) }
            Button(L10n.t(.cancel), role: .cancel) {}
        }
    }
}

private struct APIKeyRow: View {
    @EnvironmentObject var app: AppState
    let ref: ProviderRef
    var showName = true
    @State private var input = ""
    @State private var error: String?
    @State private var warning: String?
    @State private var testResult: (ok: Bool, text: String)?
    @State private var testing = false

    private var settings: AppSettings { app.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if showName {
                    Text(settings.displayName(ref)).frame(width: 140, alignment: .leading)
                }
                SecureField(L10n.t(.apiKeyPlaceholder), text: $input)
                    .onSubmit(save)
                Button(L10n.t(.save), action: save)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                if app.apiKeys[ref] != nil {
                    Button(role: .destructive) {
                        app.deleteKey(for: ref)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help(L10n.t(.delete))
                }
            }
            HStack {
                if let masked = app.maskedKey(for: ref) {
                    Text(L10n.t(.keyStored)).foregroundStyle(.green)
                    Text(masked).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                } else if !settings.requiresKey(ref) {
                    Text(L10n.t(.keyNotNeeded)).foregroundStyle(.secondary)
                } else {
                    Text(L10n.t(.keyMissing)).foregroundStyle(.secondary)
                }
                if app.isUsable(ref) {
                    Button(L10n.t(.testKey)) { Task { await test() } }
                        .controlSize(.small)
                        .disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                }
                if let url = settings.keyHelpURL(ref) {
                    Link(url.host ?? url.absoluteString, destination: url)
                }
            }
            .font(.caption)
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            if let testResult {
                Text(testResult.text).font(.caption).foregroundStyle(testResult.ok ? .green : .red)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private func save() {
        do {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            try app.saveKey(trimmed, for: ref)
            input = ""
            error = nil
            testResult = nil
            if let prefix = settings.keyPrefix(ref), !trimmed.hasPrefix(prefix) {
                warning = String(format: L10n.t(.keyFormatWarning), settings.displayName(ref), prefix)
            } else {
                warning = nil
            }
            Task { await test() }
            if !app.isUsable(settings.provider) { settings.provider = ref }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        switch await app.testKey(for: ref) {
        case .success:
            testResult = (true, L10n.t(.testOK))
        case let .failure(failure):
            testResult = (false, "\(L10n.t(.errorPrefix)): \(failure.localizedDescription)")
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
