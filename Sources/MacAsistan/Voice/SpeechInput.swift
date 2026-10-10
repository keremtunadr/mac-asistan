import AppKit
import AVFoundation
import Foundation
import Speech

/// Mikrofon + Apple Speech framework ile konuşma tanıma.
///
/// Modlar:
/// - `.off`: mikrofon kapalı
/// - `.wake`: "Hey AI" bekleniyor (sürekli dinleme)
/// - `.command`: kullanıcının sorusu dinleniyor; sessizlik algılanınca metin gönderilir
/// - `.bargeIn`: asistan sesli okurken kullanıcının araya girmesi bekleniyor
@MainActor
final class SpeechInput: ObservableObject {
    enum Mode: Equatable { case off, wake, command, bargeIn }

    @Published private(set) var mode: Mode = .off
    @Published private(set) var transcript = ""
    @Published private(set) var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published private(set) var speechStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
    @Published private(set) var onDeviceAvailable = true
    @Published var lastError: String?

    /// Dinleme bitip metin hazır olduğunda çağrılır.
    var onCommand: ((String) -> Void)?
    /// Kullanıcı sesli okuma sırasında konuşunca çağrılır.
    var onBargeIn: (() -> Void)?

    /// Uyandırma kelimesi dinlemesi açık mı (ayarlardan)
    var wakeEnabled = false
    var language: SpeechLanguage = .tr
    var silenceSeconds: Double = 1.5

    private let engine = AVAudioEngine()
    private let bufferBox = RequestBox()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var engineRunning = false

    private var silenceTimer: Timer?
    private var restartTimer: Timer?
    private var commandPrefixFromWake: String?
    private var spokenWords: Set<String> = []
    private var configObserver: NSObjectProtocol?

    var isListeningForCommand: Bool { mode == .command }
    var hasPermissions: Bool { micStatus == .authorized && speechStatus == .authorized }

    init() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleConfigurationChange() }
        }
    }

    // MARK: - İzinler

    func refreshPermissionStatus() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        speechStatus = SFSpeechRecognizer.authorizationStatus()
    }

    @discardableResult
    func requestPermissions() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        }
        refreshPermissionStatus()
        return hasPermissions
    }

    // MARK: - Dışarıdan kontrol

    /// Kullanıcı butona / kısayola bastı: soruyu dinlemeye başla.
    func startCommand() {
        Task {
            guard await requestPermissions() else {
                lastError = L10n.t(.permDenied)
                return
            }
            commandPrefixFromWake = nil
            begin(.command)
        }
    }

    /// Dinlemeyi bitir; o ana kadar söylenenler gönderilir.
    func finishCommand() {
        guard mode == .command else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        silenceTimer?.invalidate()
        returnToBackgroundMode()
        if !text.isEmpty { onCommand?(text) }
    }

    /// Dinlemeyi iptal et (metin gönderilmez).
    func cancelCommand() {
        guard mode == .command else { return }
        silenceTimer?.invalidate()
        returnToBackgroundMode()
    }

    func setWakeEnabled(_ enabled: Bool) {
        wakeEnabled = enabled
        if enabled {
            if mode == .off {
                Task {
                    guard await requestPermissions() else { return }
                    if mode == .off && wakeEnabled { begin(.wake) }
                }
            }
        } else if mode == .wake {
            stopAll()
        }
    }

    func setLanguage(_ newLanguage: SpeechLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        recognizer = nil
        if mode != .off { begin(mode) }
    }

    /// Asistan konuşmaya başladı: kullanıcının araya girmesini dinle.
    func speakingStarted(text: String) {
        spokenWords.formUnion(Self.words(in: text))
        guard hasPermissions, mode != .command, mode != .bargeIn else { return }
        begin(.bargeIn)
    }

    func speakingFinished() {
        spokenWords = []
        if mode == .bargeIn { returnToBackgroundMode() }
    }

    func stopAll() {
        generation += 1
        silenceTimer?.invalidate()
        restartTimer?.invalidate()
        task?.cancel()
        task = nil
        bufferBox.request?.endAudio()
        bufferBox.request = nil
        stopEngine()
        transcript = ""
        mode = .off
    }

    // MARK: - Tanıma oturumu

    private func returnToBackgroundMode() {
        transcript = ""
        if wakeEnabled && hasPermissions {
            begin(.wake)
        } else {
            stopAll()
        }
    }

    private func begin(_ newMode: Mode) {
        generation += 1
        let currentGeneration = generation
        silenceTimer?.invalidate()
        restartTimer?.invalidate()
        task?.cancel()
        task = nil
        bufferBox.request?.endAudio()

        if recognizer == nil || recognizer?.locale.identifier != language.rawValue {
            recognizer = SFSpeechRecognizer(locale: language.locale)
        }
        guard let recognizer else {
            lastError = "Speech recognizer unavailable for \(language.rawValue)"
            stopAll()
            return
        }
        onDeviceAvailable = recognizer.supportsOnDeviceRecognition

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = newMode == .command ? .dictation : .search
        request.addsPunctuation = newMode == .command
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        bufferBox.request = request

        mode = newMode
        commandPrefixStorage = newMode == .command ? (commandPrefixFromWake ?? "") : ""
        transcript = commandPrefixStorage

        do {
            try startEngineIfNeeded()
        } catch {
            lastError = error.localizedDescription
            stopAll()
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                self?.handle(text: text, isFinal: isFinal, failed: failed, generation: currentGeneration)
            }
        }

        switch newMode {
        case .wake, .bargeIn:
            // Uzun süren oturumları tazele (transkript kısa kalsın, sistem limitlerine takılmasın).
            restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == currentGeneration else { return }
                    self.begin(self.mode)
                }
            }
        case .command:
            // Uyandırma sonrası kullanıcıya konuşmaya başlaması için biraz daha süre tanı.
            scheduleSilenceTimer(after: max(silenceSeconds, 4), generation: currentGeneration)
        case .off:
            break
        }
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool, generation gen: Int) {
        guard gen == generation else { return }

        if let text, !text.isEmpty {
            switch mode {
            case .wake:
                if let remainder = WakeWord.match(in: text) {
                    NSSound(named: "Tink")?.play()
                    commandPrefixFromWake = remainder.isEmpty ? nil : remainder
                    begin(.command)
                    commandPrefixFromWake = nil
                    return
                }
                if text.count > 160 { begin(.wake); return }

            case .bargeIn:
                if let remainder = WakeWord.match(in: text) {
                    onBargeIn?()
                    commandPrefixFromWake = remainder.isEmpty ? nil : remainder
                    begin(.command)
                    commandPrefixFromWake = nil
                    return
                }
                // Mikrofon asistanın kendi sesini de duyabilir; okunan metinde olmayan
                // en az iki kelime duyulursa bunu kullanıcının konuşması say.
                let newWords = Self.words(in: text).subtracting(spokenWords)
                if newWords.count >= 2 {
                    onBargeIn?()
                    commandPrefixFromWake = text
                    begin(.command)
                    commandPrefixFromWake = nil
                    return
                }

            case .command:
                let prefix = commandPrefixStorage
                transcript = prefix.isEmpty ? text : prefix + " " + text
                scheduleSilenceTimer(after: silenceSeconds, generation: gen)

            case .off:
                return
            }
        }

        if isFinal || failed {
            switch mode {
            case .command:
                if transcript.trimmingCharacters(in: .whitespaces).isEmpty {
                    if failed { returnToBackgroundMode() }
                } else {
                    finishCommand()
                }
            case .wake, .bargeIn:
                // Oturum bitti/hata verdi: kısa bir beklemeden sonra yeniden başlat.
                let currentMode = mode
                restartTimer?.invalidate()
                restartTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.generation == gen, self.mode == currentMode else { return }
                        self.begin(currentMode)
                    }
                }
            case .off:
                break
            }
        }
    }

    /// Komut modunda, uyandırma ifadesinden sonra zaten söylenmiş olan kısım.
    private var commandPrefixStorage = ""

    private func scheduleSilenceTimer(after seconds: Double, generation gen: Int) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == gen, self.mode == .command else { return }
                if self.transcript.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.returnToBackgroundMode()
                } else {
                    self.finishCommand()
                }
            }
        }
    }

    // MARK: - Ses motoru

    private func startEngineIfNeeded() throws {
        guard !engineRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "MacAsistan", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input available."])
        }
        let box = bufferBox
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.append(buffer)
        }
        engine.prepare()
        try engine.start()
        engineRunning = true
    }

    private func stopEngine() {
        guard engineRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engineRunning = false
    }

    private func handleConfigurationChange() {
        // Mikrofon değişti (ör. AirPods takıldı): motoru yeniden kur.
        let currentMode = mode
        stopEngine()
        if currentMode != .off { begin(currentMode) }
    }

    // MARK: - Yardımcılar

    static func words(in text: String) -> Set<String> {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { $0.count >= 2 })
    }
}

/// Ses iş parçacığından (audio thread) güvenle erişilen istek kutusu.
final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: SFSpeechAudioBufferRecognitionRequest?

    var request: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.lock(); defer { lock.unlock() }; return _request }
        set { lock.lock(); _request = newValue; lock.unlock() }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }
}
