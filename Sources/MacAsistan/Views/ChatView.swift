import SwiftUI

struct ChatView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            ConversationList()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if !app.hasKeyForCurrentProvider {
                    MissingKeyBanner { show("settings") }
                }
                MessagesView()
                Divider()
                InputBar()
            }
        }
        .navigationTitle(app.store.selected?.title ?? L10n.t(.appName))
        .toolbar {
            ToolbarItem {
                Picker(L10n.t(.provider), selection: Binding(get: { app.settings.provider }, set: { app.settings.provider = $0 })) {
                    ForEach(AIProviderKind.allCases) { kind in
                        Text("\(kind.displayName) · \(app.settings.model(for: kind))").tag(kind)
                    }
                }
                .help(L10n.t(.provider))
            }
            ToolbarItem {
                Button {
                    show("settings")
                } label: {
                    Image(systemName: "gearshape")
                }
                .help(L10n.t(.settings))
            }
        }
        .onAppear {
            if app.openWindowAction == nil { app.openWindowAction = openWindow }
        }
    }

    private func show(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}

private struct MissingKeyBanner: View {
    var openSettings: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "key.fill").foregroundStyle(.orange)
            VStack(alignment: .leading) {
                Text(L10n.t(.noApiKey)).font(.headline)
                Text(L10n.t(.noApiKeyHint)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.t(.openSettings), action: openSettings)
        }
        .padding(10)
        .background(.orange.opacity(0.12))
    }
}

// MARK: - Sohbet listesi

private struct ConversationList: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        List(selection: Binding(get: { app.store.selectedID }, set: { app.store.selectedID = $0 })) {
            ForEach(app.store.conversations) { conversation in
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title).lineLimit(1)
                    Text(conversation.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .tag(conversation.id)
                .contextMenu {
                    Button(L10n.t(.deleteChat), role: .destructive) { app.store.delete(conversation.id) }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Button {
                app.store.newConversation()
            } label: {
                Label(L10n.t(.newChat), systemImage: "square.and.pencil").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 10)
            .padding(.top, 6)
        }
    }
}

// MARK: - Mesajlar

private struct MessagesView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        let messages = app.store.selected?.messages ?? []
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        EmptyChatView().padding(.top, 60)
                    }
                    ForEach(messages) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                    if app.isSending {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L10n.t(.thinking)).foregroundStyle(.secondary)
                        }
                        .id("thinking")
                    }
                }
                .padding(16)
            }
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: app.isSending) {
                if app.isSending { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
            .onAppear { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
        }
    }
}

private struct EmptyChatView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.tint)
            Text(L10n.t(.emptyChatTitle)).font(.title2.weight(.semibold))
            Text(L10n.t(.emptyChatText)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MessageBubble: View {
    @EnvironmentObject var app: AppState
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(attributed)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(isUser ? Color.white : Color.primary)
                HStack(spacing: 4) {
                    if message.viaVoice {
                        Image(systemName: "mic.fill")
                        Text(L10n.t(.voiceMessage))
                    }
                    if let model = message.model, !isUser {
                        Text(model)
                    }
                    Text(message.date, style: .time)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .contextMenu {
                Button(L10n.t(.copy)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                }
                if !isUser && !message.isError {
                    Button(L10n.t(.readThis)) { app.speak(message.text) }
                }
            }
            if !isUser { Spacer(minLength: 60) }
        }
    }

    private var background: Color {
        if message.isError { return .red.opacity(0.15) }
        return isUser ? .accentColor : Color(nsColor: .controlBackgroundColor)
    }

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.text, options: options)) ?? AttributedString(message.text)
    }
}

// MARK: - Yazma alanı

private struct InputBar: View {
    @EnvironmentObject var app: AppState
    @State private var text = ""
    @FocusState private var focused: Bool

    private var listening: Bool { app.speechIn.mode == .command }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if listening {
                HStack(spacing: 6) {
                    Image(systemName: "waveform").foregroundStyle(.red).symbolEffect(.variableColor.iterative)
                    Text(app.speechIn.transcript.isEmpty ? L10n.t(.listening) : app.speechIn.transcript)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            if let error = app.speechIn.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    app.toggleListening()
                } label: {
                    Image(systemName: listening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(listening ? Color.red : Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(listening ? L10n.t(.stopListening) : "\(L10n.t(.startListening)) (⌥Space)")

                TextField(L10n.t(.typeMessage), text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
                    .onSubmit(send)

                if app.speechOut.isSpeaking {
                    Button {
                        app.stopSpeaking()
                    } label: {
                        Image(systemName: "speaker.slash.circle.fill").font(.system(size: 26))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t(.stopSpeaking))
                } else {
                    Button {
                        app.settings.readAloud.toggle()
                    } label: {
                        Image(systemName: app.settings.readAloud ? "speaker.wave.2.circle.fill" : "speaker.slash.circle")
                            .font(.system(size: 26))
                            .foregroundStyle(app.settings.readAloud ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t(.readAloud))
                }

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 26))
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.isSending)
                .keyboardShortcut(.return, modifiers: .command)
                .help(L10n.t(.send))
            }
        }
        .padding(12)
        .onAppear { focused = true }
    }

    private func send() {
        let message = text
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !app.isSending else { return }
        text = ""
        app.stopSpeaking()
        Task { await app.send(message) }
    }
}
