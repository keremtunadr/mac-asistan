# Mac Asistan

Menü çubuğunda çalışan, **Türkçe, Almanca ve İngilizce** konuşan bir yapay zekâ asistanı.
Claude (Anthropic), OpenAI ve Google Gemini ile çalışır. Hem yazarak hem konuşarak kullanılabilir.

## Kurulum (programcı olmana gerek yok)

1. **İndir:** [MacAsistan.dmg](../../releases/latest/download/MacAsistan.dmg)
   (ya da sağ taraftaki **Releases** bölümünden en son sürümü seç).
2. İndirilen `MacAsistan.dmg` dosyasına çift tıkla.
3. Açılan pencerede **Mac Asistan** simgesini **Applications (Uygulamalar)** klasörüne sürükle.
4. Uygulamalar klasöründen **Mac Asistan**'ı aç.

### İlk açılışta "açılamıyor" uyarısı çıkarsa

Uygulama Apple'ın ücretli geliştirici imzasını taşımadığı için macOS ilk seferde uyarı gösterir. Bu normaldir:

- **macOS 15 (Sequoia) ve sonrası:** Uygulamayı bir kez açmayı dene ve uyarıyı kapat. Sonra
  **Sistem Ayarları › Gizlilik ve Güvenlik**'e git, aşağı kaydır ve "Mac Asistan" yanındaki
  **Yine de Aç** düğmesine bas.
- **macOS 14 (Sonoma):** Uygulamalar klasöründe Mac Asistan'a **sağ tıkla › Aç**, sonra çıkan pencerede yine **Aç**'a bas.

Bunu sadece bir kez yapman yeterli.

### İlk ayarlar

1. Uygulama açılınca **Ayarlar** penceresi gelir.
2. **Yapay Zekâ** sekmesinde kullanmak istediğin sağlayıcının API anahtarını yapıştırıp **Kaydet**'e bas:
   - Claude: <https://console.anthropic.com/settings/keys>
   - OpenAI: <https://platform.openai.com/api-keys>
   - Gemini: <https://aistudio.google.com/app/apikey>
3. Anahtarlar sadece senin Mac'indeki **Anahtar Zinciri (Keychain)**'nde saklanır. İnternete veya bu repoya yazılmaz.
   macOS anahtar zincirine erişim için izin sorarsa **Her Zaman İzin Ver**'e bas.
4. İlk kez mikrofonu kullandığında macOS **Mikrofon** ve **Konuşma Tanıma** izni ister. İkisine de izin ver.

## Kullanım

| Ne yapmak istiyorsun? | Nasıl? |
|---|---|
| Asistanı aç | Ekranın sağ üstündeki ✨ simgesine tıkla |
| Sohbet penceresi | ✨ › **Sohbet penceresini aç** |
| Konuşarak sor | Mikrofon düğmesine bas veya **⌥ Option + Boşluk** |
| Eller serbest | Ayarlar'dan **"Hey AI" ile uyandır**'ı aç, sonra "Hey AI, yarın hava nasıl?" de |
| Konuşma dilini değiştir | ✨ menüsünde **TR / DE / EN** düğmeleri |
| Sesli okumayı durdur | Konuşmaya başla, durdur düğmesine bas veya ⌥ Option + Boşluk |
| Arayüz dili | Ayarlar › Genel › Arayüz dili |
| Hangi yapay zekâ kullanılsın? | Sohbet penceresinin sağ üstündeki seçici: **✨ Otomatik** veya istediğin sağlayıcı |
| Başka yapay zekâ ekle | Ayarlar › Yapay Zekâ › **Diğer yapay zekâlar › Yapay zekâ ekle** |

- Konuşman bitince (kısa bir sessizlikten sonra) mesaj kendiliğinden gönderilir. Bekleme süresi Ayarlar › Ses'ten ayarlanır.
- **Otomatik modda** önce tercih ettiğin sağlayıcı denenir. Anahtarı, kredisi ya da modeli çalışmazsa anahtarı kayıtlı bir sonraki sağlayıcıya geçilir.
- **Başka yapay zekâlar:** DeepSeek, Mistral, Groq, xAI Grok, OpenRouter, Perplexity, Ollama ve LM Studio hazır olarak listede. "Diğer (OpenAI uyumlu)" seçeneğiyle OpenAI uyumlu API sunan herhangi bir servisi adres, model ve anahtar girerek ekleyebilirsin. İstediğin kadar ekleyebilirsin.
- Asistan, sen hangi dilde yazarsan ya da konuşursan o dilde cevap verir.
- Cevaplar dil otomatik algılanarak sesli okunur: Türkçe → **Yelda**, Almanca → **Anna**, İngilizce → **Samantha**.
  Daha doğal sesler için **Sistem Ayarları › Erişilebilirlik › Seslendirilmiş İçerik › Sistem Sesi › Sesleri Yönet** bölümünden bu seslerin "Gelişmiş" (Enhanced) ya da "Premium" sürümlerini indirebilirsin.
- Konuşma tanıma mümkün olduğunda **cihaz üzerinde** çalışır. Dil paketi yoksa **Sistem Ayarları › Klavye › Dikte** bölümünden indirebilirsin.
- Sohbet geçmişi sadece bu Mac'te tutulur: `~/Library/Application Support/MacAsistan/history.json`

### Kaynaklı mod (Strahlentherapie)

Sohbet penceresinin üstündeki **📚 Kaynaklı mod** düğmesiyle açılır. Bu modda:

- Cevaplar **yalnızca** Bilgi bankasına eklediğin kaynaklardan verilir (PDF, kılavuz, URL, DOI). Kaynakları **📚 › Bilgi bankası** penceresinden eklersin; taranmış PDF'ler cihaz üzerinde OCR ile okunur.
- Soru, Almanca ve İngilizce arama terimlerine çevrilir ve kaynaklarda **yerel olarak** aranır. Uygun bir pasaj yoksa sabit "bulunamadı" cevabı verilir.
- Kaynak listesini (başlık, yıl, sürüm, sayfa, bölüm, bağlantı) yapay zekâ değil **uygulama** oluşturur. Yapay zekânın verdiği her alıntı ilgili sayfada birebir aranır: ✓ doğrulandı, ⚠ kontrol et.
- 🔍 düğmesi PDF'i ilgili sayfada açar ve alıntıyı vurgular.
- Varsayılan cevap dili Almancadır. Türkçe sorarsan Türkçe, İngilizce sorarsan İngilizce cevap gelir.
- Klinik karar desteği içindir; tedavi kararı vermez. Tanımlanabilir hasta bilgisi girme: soru ve ilgili pasajlar seçili yapay zekâ sağlayıcısına gönderilir.

**Gereksinimler:** macOS 14 Sonoma veya daha yenisi. Apple Silicon (M1/M2/M3/M4…) ve Intel Mac'lerde çalışır.

---

## Geliştiriciler için

Xcode projesi yoktur. Uygulama **Swift Package Manager** ile komut satırından derlenir.

```bash
./scripts/build-app.sh          # dist/Mac Asistan.app ve dist/MacAsistan.dmg üretir (macOS gerekir)
```

- **Otomatik derleme:** `.github/workflows/build.yml` her gönderimde macOS üzerinde universal (arm64 + x86_64) derleme yapar ve DMG'yi Actions çıktısı olarak saklar.
- **`main` dalı:** Her gönderimde **son-surum** adlı GitHub Release güncellenir. Yukarıdaki indirme bağlantısı her zaman en yeni DMG'yi verir.
- **`v1.2.3` gibi bir etiket:** O sürüm numarasıyla ayrı bir Release oluşturur.

### İsteğe bağlı: Apple imzası ve notarizasyon

Apple Developer hesabın varsa şu GitHub Secrets değerlerini eklediğinde uyarısız açılan, imzalı ve notarize edilmiş DMG üretilir:

| Secret | Açıklama |
|---|---|
| `MACOS_CERTIFICATE` | Developer ID Application sertifikası (.p12, base64) |
| `MACOS_CERTIFICATE_PASSWORD` | .p12 parolası |
| `MACOS_SIGN_IDENTITY` | Örn. `Developer ID Application: Ad Soyad (TEAMID)` |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | Notarizasyon için (uygulamaya özel parola) |

### Proje yapısı

```
Sources/MacAsistan/
  App/        Uygulama girişi (menü çubuğu + pencereler), AppState (merkezi mantık)
  AI/         Anthropic, OpenAI, Gemini istemcileri
  Chat/       Yerel sohbet geçmişi
  Voice/      Konuşma tanıma, "Hey AI", sesli okuma, ⌥Space kısayolu
  Views/      SwiftUI ekranları
  Support/    Ayarlar, Keychain, çoklu dil metinleri (TR/DE/EN)
Resources/    Info.plist, izin açıklamaları, entitlements
scripts/      build-app.sh (derleme + DMG), make-icon.swift (simge)
```
