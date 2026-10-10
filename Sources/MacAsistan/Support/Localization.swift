import Foundation

/// Arayüz dili (UI). Konuşma tanıma dilinden bağımsızdır.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case tr, de, en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tr: return "Türkçe"
        case .de: return "Deutsch"
        case .en: return "English"
        }
    }

    var englishName: String {
        switch self {
        case .tr: return "Turkish"
        case .de: return "German"
        case .en: return "English"
        }
    }
}

/// Uygulama içindeki tüm metinlerin anahtarları.
enum LKey: String {
    case appName
    case openChat, settings, quit, newChat, conversations, deleteChat, clearHistory, clearHistoryConfirm, cancel
    case typeMessage, send, thinking, copy, readThis
    case listening, startListening, stopListening, speaking, stopSpeaking, idle, wakeWaiting
    case readAloud, wakeWord, wakeWordHint, hotkey, hotkeyHint
    case speechLanguage, uiLanguage
    case provider, model, modelHint, loadModels, modelsLoaded, apiKeys, apiKeyPlaceholder, save, delete
    case keyStored, keyMissing, keyNotSet, keySavedInKeychain
    case noApiKey, noApiKeyHint, openSettings
    case tabGeneral, tabAI, tabVoice, tabData, tabAbout
    case welcomeTitle, welcomeText
    case silenceDelay, seconds
    case permissions, permMic, permSpeech, permGranted, permDenied, permUnknown, requestPermissions, openPrivacySettings
    case onDeviceYes, onDeviceNo
    case voicesTitle, voiceNotFound
    case historyLocation, openFolder
    case aboutText
    case errorPrefix, refusal, emptyAnswer, voiceMessage
    case emptyChatTitle, emptyChatText
    case untitledChat
    case otherAIs, otherAIsHint, addAI, customOpenAI, newAIName, name, baseURL, removeAI, removeAIConfirm, keyRequired, keyNotNeeded
    case showInDock
    case evidenceMode, evidenceModeHint, evidenceBanner, library, libraryTitle, addPDF, addLink, linkPlaceholder, add
    case docTitle, docAuthors, docYear, docVersion, docURL, docDOI, docPages, docChunks, docOCR, docAdded, docProcessing, docFailed, docReady
    case libraryEmpty, libraryPrivacy, sources, openSource, quoteVerified, quoteUnverified, quoteMissing, searchingSources, openInPreview
    case speed, speedFast, speedBalanced, speedDeep, speedHint
    case automatic, autoSelect, autoSelectHint, allProvidersFailed, preferredProvider
    case testKey, testOK, keyFormatWarning, hintInvalidKey, hintModelNotFound, hintBilling
}

enum L10n {
    /// Seçili arayüz diline göre metni döndürür.
    @MainActor
    static func t(_ key: LKey) -> String {
        t(key, AppSettings.shared.uiLanguage)
    }

    static func t(_ key: LKey, _ lang: AppLanguage) -> String {
        guard let entry = table[key] else { return key.rawValue }
        switch lang {
        case .tr: return entry.0
        case .de: return entry.1
        case .en: return entry.2
        }
    }

    // (Türkçe, Deutsch, English)
    private static let table: [LKey: (String, String, String)] = [
        .appName: ("Mac Asistan", "Mac Asistan", "Mac Asistan"),
        .openChat: ("Sohbet penceresini aç", "Chatfenster öffnen", "Open chat window"),
        .settings: ("Ayarlar", "Einstellungen", "Settings"),
        .quit: ("Çıkış", "Beenden", "Quit"),
        .newChat: ("Yeni sohbet", "Neuer Chat", "New chat"),
        .conversations: ("Sohbetler", "Unterhaltungen", "Conversations"),
        .deleteChat: ("Sohbeti sil", "Chat löschen", "Delete chat"),
        .clearHistory: ("Tüm geçmişi sil", "Gesamten Verlauf löschen", "Delete all history"),
        .clearHistoryConfirm: ("Tüm sohbet geçmişi silinsin mi? Bu işlem geri alınamaz.",
                               "Den gesamten Chatverlauf löschen? Das kann nicht rückgängig gemacht werden.",
                               "Delete the entire chat history? This cannot be undone."),
        .cancel: ("Vazgeç", "Abbrechen", "Cancel"),
        .typeMessage: ("Mesajını yaz… (Enter ile gönder)", "Nachricht eingeben… (Enter zum Senden)", "Type a message… (Enter to send)"),
        .send: ("Gönder", "Senden", "Send"),
        .thinking: ("Düşünüyor…", "Denkt nach…", "Thinking…"),
        .copy: ("Kopyala", "Kopieren", "Copy"),
        .readThis: ("Sesli oku", "Vorlesen", "Read aloud"),
        .listening: ("Dinliyorum…", "Ich höre zu…", "Listening…"),
        .startListening: ("Dinlemeyi başlat", "Zuhören starten", "Start listening"),
        .stopListening: ("Dinlemeyi durdur", "Zuhören beenden", "Stop listening"),
        .speaking: ("Konuşuyor…", "Spricht…", "Speaking…"),
        .stopSpeaking: ("Okumayı durdur", "Vorlesen stoppen", "Stop speaking"),
        .idle: ("Hazır", "Bereit", "Ready"),
        .wakeWaiting: ("\"Hey AI\" bekleniyor", "Warte auf \"Hey AI\"", "Waiting for \"Hey AI\""),
        .readAloud: ("Cevapları sesli oku", "Antworten vorlesen", "Read answers aloud"),
        .wakeWord: ("\"Hey AI\" ile uyandır", "Mit \"Hey AI\" aktivieren", "Wake with \"Hey AI\""),
        .wakeWordHint: ("Açıkken mikrofon sürekli dinler (cihaz üzerinde). \"Hey AI\" deyip sorunu söyle.",
                        "Wenn aktiv, hört das Mikrofon ständig zu (auf dem Gerät). Sag \"Hey AI\" und dann deine Frage.",
                        "When on, the microphone listens continuously (on device). Say \"Hey AI\" followed by your question."),
        .hotkey: ("⌥ + Boşluk ile dinlemeyi başlat", "Zuhören mit ⌥ + Leertaste starten", "Start listening with ⌥ + Space"),
        .hotkeyHint: ("Her uygulamadan çalışır.", "Funktioniert in jeder App.", "Works from any app."),
        .speechLanguage: ("Konuşma tanıma dili", "Spracherkennungssprache", "Speech recognition language"),
        .uiLanguage: ("Arayüz dili", "Sprache der Oberfläche", "Interface language"),
        .provider: ("Yapay zekâ sağlayıcısı", "KI-Anbieter", "AI provider"),
        .model: ("Model", "Modell", "Model"),
        .modelHint: ("Listeden seç veya model adını elle yaz.", "Aus der Liste wählen oder Modellnamen eingeben.", "Pick from the list or type a model name."),
        .loadModels: ("Modelleri yükle", "Modelle laden", "Load models"),
        .modelsLoaded: ("model bulundu", "Modelle gefunden", "models found"),
        .apiKeys: ("API anahtarları", "API-Schlüssel", "API keys"),
        .apiKeyPlaceholder: ("API anahtarını yapıştır", "API-Schlüssel einfügen", "Paste API key"),
        .save: ("Kaydet", "Speichern", "Save"),
        .delete: ("Sil", "Löschen", "Delete"),
        .keyStored: ("Kayıtlı ✓", "Gespeichert ✓", "Saved ✓"),
        .keyMissing: ("Anahtar yok", "Kein Schlüssel", "No key"),
        .keyNotSet: ("API anahtarı girilmemiş", "Kein API-Schlüssel hinterlegt", "No API key set"),
        .keySavedInKeychain: ("Anahtarlar yalnızca bu Mac'in Anahtar Zinciri'nde (Keychain) saklanır.",
                              "Schlüssel werden nur im Schlüsselbund dieses Macs gespeichert.",
                              "Keys are stored only in this Mac's Keychain."),
        .noApiKey: ("API anahtarı eksik", "API-Schlüssel fehlt", "API key missing"),
        .noApiKeyHint: ("Seçili sağlayıcı için Ayarlar'dan bir API anahtarı gir.",
                        "Bitte in den Einstellungen einen API-Schlüssel für den gewählten Anbieter eingeben.",
                        "Enter an API key for the selected provider in Settings."),
        .openSettings: ("Ayarları aç", "Einstellungen öffnen", "Open Settings"),
        .tabGeneral: ("Genel", "Allgemein", "General"),
        .tabAI: ("Yapay Zekâ", "KI", "AI"),
        .tabVoice: ("Ses", "Sprache", "Voice"),
        .tabData: ("Veriler", "Daten", "Data"),
        .tabAbout: ("Hakkında", "Über", "About"),
        .welcomeTitle: ("Mac Asistan'a hoş geldin!", "Willkommen bei Mac Asistan!", "Welcome to Mac Asistan!"),
        .welcomeText: ("Başlamak için kullanmak istediğin sağlayıcının API anahtarını aşağıya yapıştırıp Kaydet'e bas.",
                       "Füge zum Start unten den API-Schlüssel deines Anbieters ein und klicke auf Speichern.",
                       "To get started, paste the API key of the provider you want to use below and click Save."),
        .silenceDelay: ("Sessizlikten sonra otomatik gönder", "Nach Stille automatisch senden", "Auto-send after silence"),
        .seconds: ("sn", "s", "s"),
        .permissions: ("İzinler", "Berechtigungen", "Permissions"),
        .permMic: ("Mikrofon", "Mikrofon", "Microphone"),
        .permSpeech: ("Konuşma tanıma", "Spracherkennung", "Speech recognition"),
        .permGranted: ("İzin verildi", "Erlaubt", "Granted"),
        .permDenied: ("Reddedildi", "Abgelehnt", "Denied"),
        .permUnknown: ("Henüz sorulmadı", "Noch nicht gefragt", "Not asked yet"),
        .requestPermissions: ("İzin iste", "Berechtigung anfragen", "Request permission"),
        .openPrivacySettings: ("Sistem Ayarları › Gizlilik", "Systemeinstellungen › Datenschutz", "System Settings › Privacy"),
        .onDeviceYes: ("Bu dil cihaz üzerinde tanınıyor (internet gerekmez).",
                       "Diese Sprache wird auf dem Gerät erkannt (kein Internet nötig).",
                       "This language is recognized on device (no internet needed)."),
        .onDeviceNo: ("Bu dil için cihaz üzeri tanıma yok; Apple sunucusu kullanılacak. Sistem Ayarları › Klavye › Dikte bölümünden dil paketini indirebilirsin.",
                      "Für diese Sprache gibt es keine Erkennung auf dem Gerät; Apple-Server werden genutzt. Lade das Sprachpaket unter Systemeinstellungen › Tastatur › Diktat.",
                      "On-device recognition isn't available for this language; Apple's servers will be used. Download the language under System Settings › Keyboard › Dictation."),
        .voicesTitle: ("Okuma sesleri", "Vorlesestimmen", "Reading voices"),
        .voiceNotFound: ("ses bulunamadı – Sistem Ayarları › Erişilebilirlik › Seslendirilmiş İçerik'ten indirebilirsin",
                         "keine Stimme – unter Systemeinstellungen › Bedienungshilfen › Gesprochene Inhalte laden",
                         "no voice – download one in System Settings › Accessibility › Spoken Content"),
        .historyLocation: ("Sohbet geçmişi yalnızca bu Mac'te saklanır:", "Der Chatverlauf wird nur auf diesem Mac gespeichert:", "Chat history is stored only on this Mac:"),
        .openFolder: ("Klasörü göster", "Ordner zeigen", "Show folder"),
        .aboutText: ("Menü çubuğunda çalışan, Claude, OpenAI ve Gemini destekli, sesli ve yazılı çok dilli asistan.",
                     "Mehrsprachiger Sprach- und Text-Assistent in der Menüleiste – mit Claude, OpenAI und Gemini.",
                     "A multilingual voice and text assistant in your menu bar, powered by Claude, OpenAI and Gemini."),
        .errorPrefix: ("Hata", "Fehler", "Error"),
        .refusal: ("Model bu isteği yanıtlamayı reddetti.", "Das Modell hat die Anfrage abgelehnt.", "The model declined to answer this request."),
        .emptyAnswer: ("Model boş bir cevap döndürdü.", "Das Modell hat eine leere Antwort geliefert.", "The model returned an empty answer."),
        .voiceMessage: ("Sesli mesaj", "Sprachnachricht", "Voice message"),
        .emptyChatTitle: ("Nasıl yardımcı olabilirim?", "Wie kann ich helfen?", "How can I help?"),
        .emptyChatText: ("Yaz ya da mikrofona bas. Türkçe, Almanca veya İngilizce konuşabilirsin.",
                         "Schreib oder tippe aufs Mikrofon. Du kannst Türkisch, Deutsch oder Englisch sprechen.",
                         "Type or tap the microphone. You can speak Turkish, German or English."),
        .untitledChat: ("Yeni sohbet", "Neuer Chat", "New chat"),
        .otherAIs: ("Diğer yapay zekâlar", "Weitere KIs", "Other AIs"),
        .otherAIsHint: ("OpenAI uyumlu API sunan her servisi ekleyebilirsin: DeepSeek, Mistral, Groq, xAI, OpenRouter, Perplexity, bilgisayarında çalışan Ollama veya LM Studio …",
                        "Du kannst jeden Dienst mit OpenAI-kompatibler API hinzufügen: DeepSeek, Mistral, Groq, xAI, OpenRouter, Perplexity, lokal laufendes Ollama oder LM Studio …",
                        "You can add any service with an OpenAI-compatible API: DeepSeek, Mistral, Groq, xAI, OpenRouter, Perplexity, Ollama or LM Studio running on your Mac …"),
        .addAI: ("Yapay zekâ ekle", "KI hinzufügen", "Add AI"),
        .customOpenAI: ("Diğer (OpenAI uyumlu)…", "Andere (OpenAI-kompatibel)…", "Other (OpenAI-compatible)…"),
        .newAIName: ("Yeni yapay zekâ", "Neue KI", "New AI"),
        .name: ("Ad", "Name", "Name"),
        .baseURL: ("Adres (URL)", "Adresse (URL)", "Address (URL)"),
        .removeAI: ("Kaldır", "Entfernen", "Remove"),
        .removeAIConfirm: ("Bu yapay zekâ ve anahtarı kaldırılsın mı?", "Diese KI und ihren Schlüssel entfernen?", "Remove this AI and its key?"),
        .keyRequired: ("API anahtarı gerekli", "API-Schlüssel erforderlich", "API key required"),
        .keyNotNeeded: ("Anahtar gerekmiyor", "Kein Schlüssel nötig", "No key needed"),
        .speed: ("Cevap hızı", "Antworttempo", "Response speed"),
        .speedFast: ("Hızlı", "Schnell", "Fast"),
        .speedBalanced: ("Dengeli", "Ausgewogen", "Balanced"),
        .speedDeep: ("Derin düşün", "Gründlich", "Thorough"),
        .speedHint: ("Hızlı: günlük sohbet ve sesli kullanım için. Derin düşün: zor sorular için, daha yavaş ve daha pahalı. Daha da hız için daha küçük bir model seç (ör. claude-haiku-5-5).",
                     "Schnell: für Alltag und Sprachbedienung. Gründlich: für schwierige Fragen, langsamer und teurer. Noch schneller: ein kleineres Modell wählen (z. B. claude-haiku-5-5).",
                     "Fast: for everyday chat and voice. Thorough: for hard questions, slower and more expensive. For even more speed pick a smaller model (e.g. claude-haiku-5-5)."),
        .evidenceMode: ("Kaynaklı mod (Strahlentherapie)", "Quellenmodus (Strahlentherapie)", "Source mode (radiation oncology)"),
        .evidenceModeHint: ("Açıkken cevaplar yalnızca bilgi bankandaki kaynaklardan verilir; her bilgi sayfa numarasıyla kaynaklanır ve alıntılar kaynakta doğrulanır.",
                            "Wenn aktiv, wird ausschließlich aus Ihrer Wissensdatenbank geantwortet; jede Aussage wird mit Seitenangabe belegt und die Zitate werden in der Quelle geprüft.",
                            "When on, answers come only from your knowledge base; every statement is cited with its page and quotes are checked against the source."),
        .evidenceBanner: ("Kaynaklı mod açık: yalnızca bilgi bankasındaki %d kaynak kullanılır.",
                          "Quellenmodus aktiv: nur %d Quellen aus Ihrer Wissensdatenbank werden verwendet.",
                          "Source mode on: only the %d sources in your knowledge base are used."),
        .library: ("Bilgi bankası", "Wissensdatenbank", "Knowledge base"),
        .libraryTitle: ("Bilgi bankası – onaylı kaynaklar", "Wissensdatenbank – freigegebene Quellen", "Knowledge base – approved sources"),
        .addPDF: ("PDF ekle…", "PDF hinzufügen…", "Add PDF…"),
        .addLink: ("URL / DOI ekle", "URL / DOI hinzufügen", "Add URL / DOI"),
        .linkPlaceholder: ("https://… veya 10.1016/…", "https://… oder 10.1016/…", "https://… or 10.1016/…"),
        .add: ("Ekle", "Hinzufügen", "Add"),
        .docTitle: ("Başlık", "Titel", "Title"),
        .docAuthors: ("Yazarlar / kurum", "Autoren / Organisation", "Authors / organisation"),
        .docYear: ("Yıl", "Jahr", "Year"),
        .docVersion: ("Sürüm / güncelleme", "Version / Stand", "Version / update"),
        .docURL: ("URL", "URL", "URL"),
        .docDOI: ("DOI", "DOI", "DOI"),
        .docPages: ("sayfa", "Seiten", "pages"),
        .docChunks: ("parça", "Abschnitte", "passages"),
        .docOCR: ("OCR ile okunan sayfa", "per OCR gelesene Seiten", "pages read via OCR"),
        .docAdded: ("Eklendi", "Hinzugefügt", "Added"),
        .docProcessing: ("İşleniyor…", "Wird verarbeitet…", "Processing…"),
        .docFailed: ("Hata", "Fehler", "Failed"),
        .docReady: ("Hazır", "Bereit", "Ready"),
        .libraryEmpty: ("Henüz kaynak yok. PDF'leri buraya sürükle ya da \"PDF ekle\" ile seç; URL veya DOI de ekleyebilirsin.",
                        "Noch keine Quellen. Ziehen Sie PDFs hierher oder wählen Sie \"PDF hinzufügen\"; URLs oder DOIs sind ebenfalls möglich.",
                        "No sources yet. Drag PDFs here or use \"Add PDF\"; you can also add URLs or DOIs."),
        .libraryPrivacy: ("Kaynaklar yalnızca bu Mac'te saklanır ve yerel olarak aranır. Soru sorduğunda, sorun ve en ilgili pasajlar seçili yapay zekâ sağlayıcısına gönderilir. Tanımlanabilir hasta bilgisi girme.",
                          "Quellen werden nur auf diesem Mac gespeichert und lokal durchsucht. Bei einer Frage werden die Frage und die relevantesten Passagen an den gewählten KI-Anbieter gesendet. Keine identifizierbaren Patientendaten eingeben.",
                          "Sources are stored only on this Mac and searched locally. When you ask, your question and the most relevant passages are sent to the selected AI provider. Do not enter identifiable patient data."),
        .sources: ("Kaynaklar", "Quellen", "Sources"),
        .openSource: ("Kaynağı aç", "Quelle öffnen", "Open source"),
        .quoteVerified: ("Alıntı kaynakta doğrulandı", "Zitat in der Quelle verifiziert", "Quote verified in source"),
        .quoteUnverified: ("Alıntı kaynakta birebir bulunamadı – kontrol et", "Zitat nicht wörtlich in der Quelle gefunden – bitte prüfen", "Quote not found verbatim in source – please check"),
        .quoteMissing: ("Alıntı verilmedi – kontrol et", "Kein Zitat angegeben – bitte prüfen", "No quote given – please check"),
        .searchingSources: ("Kaynaklarda aranıyor…", "Quellen werden durchsucht…", "Searching sources…"),
        .openInPreview: ("Önizleme'de aç", "In Vorschau öffnen", "Open in Preview"),
        .showInDock: ("Dock'ta göster", "Im Dock anzeigen", "Show in Dock"),
        .automatic: ("Otomatik", "Automatisch", "Automatic"),
        .autoSelect: ("Sağlayıcıyı otomatik seç", "Anbieter automatisch wählen", "Choose provider automatically"),
        .autoSelectHint: ("Önce tercih ettiğin sağlayıcı denenir. Anahtarı, kredisi veya modeli çalışmazsa ya da sunucu cevap vermezse anahtarı kayıtlı diğer sağlayıcıya geçilir.",
                          "Zuerst wird dein bevorzugter Anbieter genutzt. Funktionieren Schlüssel, Guthaben oder Modell nicht oder antwortet der Server nicht, wird ein anderer Anbieter mit gespeichertem Schlüssel verwendet.",
                          "Your preferred provider is tried first. If its key, credit or model doesn't work or the server doesn't respond, another provider with a saved key is used."),
        .allProvidersFailed: ("Hiçbir sağlayıcı cevap veremedi:", "Kein Anbieter konnte antworten:", "No provider could answer:"),
        .preferredProvider: ("Tercih edilen sağlayıcı", "Bevorzugter Anbieter", "Preferred provider"),
        .testKey: ("Test et", "Testen", "Test"),
        .testOK: ("Anahtar çalışıyor ✓", "Schlüssel funktioniert ✓", "Key works ✓"),
        .keyFormatWarning: ("Bu bir %@ anahtarına benzemiyor. Gerçek anahtar \"%@\" ile başlar. Anahtarın kimliğini (ID) değil, oluşturulurken bir kez gösterilen anahtarın tamamını kopyala.",
                            "Das sieht nicht wie ein %@-Schlüssel aus. Echte Schlüssel beginnen mit \"%@\". Kopiere den vollständigen Schlüssel, der beim Erstellen einmal angezeigt wird – nicht die ID.",
                            "This doesn't look like a %@ key. Real keys start with \"%@\". Copy the full key shown once when it's created – not the key ID."),
        .hintInvalidKey: ("İpucu: Anahtar geçersiz. Ayarlar › Yapay Zekâ'da anahtarı sil, sağlayıcının sitesinde yeni bir anahtar oluştur ve tamamını yapıştır. Ardından \"Test et\" düğmesiyle dene.",
                          "Tipp: Der Schlüssel ist ungültig. Lösche ihn unter Einstellungen › KI, erstelle beim Anbieter einen neuen und füge ihn vollständig ein. Prüfe ihn dann mit \"Testen\".",
                          "Tip: The key is invalid. Delete it in Settings › AI, create a new key on the provider's site and paste it completely. Then check it with \"Test\"."),
        .hintModelNotFound: ("İpucu: Bu model kullanılamıyor. Ayarlar › Yapay Zekâ'da \"Modelleri yükle\" düğmesine bas ve listeden güncel bir model seç.",
                             "Tipp: Dieses Modell ist nicht verfügbar. Klicke unter Einstellungen › KI auf \"Modelle laden\" und wähle ein aktuelles Modell.",
                             "Tip: This model isn't available. In Settings › AI click \"Load models\" and pick a current model."),
        .hintBilling: ("İpucu: Hesabında kredi/kota kalmamış olabilir. Sağlayıcının sitesinde Billing (ödeme) bölümünü kontrol et.",
                       "Tipp: Möglicherweise ist dein Guthaben/Kontingent aufgebraucht. Prüfe den Bereich Billing beim Anbieter.",
                       "Tip: Your credit or quota may be used up. Check the Billing section on the provider's site."),
    ]
}
